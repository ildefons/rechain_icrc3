import Map "mo:map/Map";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import SWB "mo:swb/Stable";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import CertifiedData "mo:base/CertifiedData";
import Error "mo:base/Error";
import T "./types";
import Vec "mo:vector";
import RepIndy "mo:rep-indy-hash";
import Text "mo:base/Text";
import Timer "mo:base/Timer";
import Archive "./archive";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import Iter "mo:base/Iter";
import Bool "mo:base/Bool";
import CertTree "mo:cert/CertTree";
import MTree "mo:cert/MerkleTree";
import Option "mo:base/Option";
import Utils "./utils";

module {

  public type Mem = {
    history : SWB.StableData<T.Value>;
    var phash : ?Blob;
    var lastIndex : Nat;
    var firstIndex : Nat;
    var canister : ?Principal;
    archives : Map.Map<Principal, T.TransactionRange>;
    cert_store : CertTree.Store;
  };

  public func Mem() : Mem {
    {
      history = SWB.SlidingWindowBufferNewMem<T.Value>();
      var phash = null;
      var lastIndex = 0;
      var firstIndex = 0;
      var canister = null;
      archives = Map.new<Principal, T.TransactionRange>();
      cert_store = CertTree.newStore(); //Certificate tree storage
    };
  };
  public type Value = T.Value;
  public type GetBlocksArgs = T.GetBlocksArgs;
  public type GetBlocksResult = T.GetBlocksResult;
  public type GetArchivesArgs = T.GetArchivesArgs;
  public type GetArchivesResult = T.GetArchivesResult;

  public type ActionReducer<A, B> = (A) -> ReducerResponse<B>;
  public type BlockId = Nat;
  public type ReducerResponse<E> = {
    #Ok : (BlockId) -> ();
    #Pass;
    #Err : E;
  };
  public type GetBlocksRequest = { start : Nat; length : Nat };
  public type GetTransactionsResponse = {
    first_index : Nat;
    log_length : Nat;
    transactions : [T.Value];
    archived_transactions : [ArchivedRange];
  };
  public type ArchivedRange = {
    callback : shared query GetBlocksRequest -> async T.TransactionRange;
    start : Nat;
    length : Nat;
  };

  public type Transaction = T.Value;
  public type AddTransactionsResponse = T.AddTransactionsResponse;

  public let DEFAULT_SETTINGS = {
    archiveActive = true;
    maxActiveRecords = 2000; // max size of ledger before archiving 
    settleToRecords = 1000; //It makes sure to leave 1000 records in the ledger after archiving
    maxRecordsInArchiveInstance = 10_000_000; //if archive full, we create a new one
    maxArchivePages = 62500; //Archive constructor parameter: every page is 65536 per KiB. 62500 pages is default size (4 Gbytes)
    archiveIndexType = #Stable;
    maxRecordsToArchive = 10_000; // maximum number of blocks archived every archiving cycle. if bigger, a new time is started and the archiving function is called again
    archiveCycles = 2_000_000_000_000; //two trillion: cycle requirement to create an archive canister
    archiveControllers = [];
    supportedBlocks = [];
  } : T.InitArgs;

  public class Chain<A, E>({
    mem : Mem;
    encodeBlock : (A) -> T.Value;
    reducers : [ActionReducer<A, E>];
    settings : ?T.InitArgs;
  }) {

    let history = SWB.SlidingWindowBuffer<T.Value>(mem.history);

    let archiveState = {
      var bCleaning = false; //It indicates whether a archival process is on or not (only 1 possible at a time)
      var cleaningTimer : ?Nat = null; //This timer will be set once we reach a ledger size > maxActiveRecords (see mothod below)
      settings = Option.get(settings, DEFAULT_SETTINGS);
   
    };



    public func dispatch<system>(action : A) : ({ #Ok : BlockId; #Err : E }) {
      // Execute reducers
      let reducerResponse = Array.map<ActionReducer<A, E>, ReducerResponse<E>>(reducers, func(fn) = fn(action));
      // Check if any reducer returned an error and terminate if so
      let hasError = Array.find<ReducerResponse<E>>(reducerResponse, func(resp) = switch (resp) { case (#Err(_)) true; case (_) false });

      switch (hasError) { case (? #Err(e)) { return #Err(e) }; case (_) () };
      let blockId = mem.lastIndex + 1; //archiveState.history.end() + 1; // ILDE: now archiveState.lastIndex is the id of last block in the ledger
      // Execute state changes if no errors
      ignore Array.map<ReducerResponse<E>, ()>(reducerResponse, func(resp) { let #Ok(f) = resp else return (); f(blockId) });

      if (archiveState.settings.archiveActive) {
        let encodedBlock : T.Value = encodeBlock(action);
        // create new empty block entry
        let trx = Vec.new<(Text, T.Value)>();
        // Add phash to empty block (null if not the first block)
        switch (mem.phash) {
          case (null) {};
          case (?val) {
            Vec.add(trx, ("phash", #Blob(val)));
          };
        };
        // add encoded blockIlde to new block with phash
        Vec.add(trx, ("tx", encodedBlock));
        // covert vector to map to make it consistent with Value type
        let thisTrx = #Map(Vec.toArray(trx));
        mem.phash := ?Blob.fromArray(RepIndy.hash_val(thisTrx));
        ignore history.add(thisTrx);
        //One we add the block, we need to increase the lastIndex
        mem.lastIndex := mem.lastIndex + 1;

        if (history.len() > archiveState.settings.maxActiveRecords) {
          switch (archiveState.cleaningTimer) {
            case (null) {
              //only need one active timer
              archiveState.cleaningTimer := ?Timer.setTimer<system>(#seconds(0), check_clean_up);
            };
            case (_) {};
          };
        };

        dispatch_cert();
      };

      #Ok(blockId);
    };

    public func upgrade_archives() : async () {

      for (archivePrincipal in Map.keys(mem.archives)) {
        let archiveActor = actor (Principal.toText(archivePrincipal)) : T.ArchiveInterface;
        let ArchiveMgr = (system Archive.archive)(#upgrade archiveActor);
        ignore await ArchiveMgr(null); // No change in settings
      };
    };

    private func new_archive<system>(initArg : T.ArchiveInitArgs) : async ?(actor {}) {
      let ?this_canister = mem.canister else Debug.trap("No canister set");

      if (ExperimentalCycles.balance() > archiveState.settings.archiveCycles * 2) {
        ExperimentalCycles.add<system>(archiveState.settings.archiveCycles);
      } else {
        //warning ledger will eventually overload
        Debug.print("Not enough cycles" # debug_show (ExperimentalCycles.balance()));
        archiveState.bCleaning := false;
        return null;
      };

      let ArchiveMgr = (system Archive.archive)(
        #new {
          settings = ?{
            controllers = ?Array.append([this_canister], archiveState.settings.archiveControllers);
            compute_allocation = null;
            memory_allocation = null;
            freezing_threshold = null;
          };
        }
      );

      try {
        return ?(await ArchiveMgr(?initArg));
      } catch (err) {
        archiveState.bCleaning := false;
        Debug.print("Error creating archive canister " # Error.message(err));
        return null;
      };

    };

    private func dispatch_cert() : () {
      let ?latest_hash = mem.phash else return;

      let ct = CertTree.Ops(mem.cert_store);
      ct.put([Text.encodeUtf8("last_block_index")], Utils.encodeBigEndian(mem.lastIndex));
      ct.put([Text.encodeUtf8("last_block_hash")], latest_hash);
      ct.setCertifiedData();
    };


    public func check_clean_up<system>() : async () {

      //clear the timer
      archiveState.cleaningTimer := null;

      //ensure only one cleaning job is running

      if (archiveState.bCleaning) {
        return; //only one cleaning at a time;
      };

      if (history.len() < archiveState.settings.maxActiveRecords) return;

      // let know that we are creating an archive canister so noone else try at the same time

      archiveState.bCleaning := true;

      //cleaning

      let (archive_detail, available_capacity) = if (Map.size(mem.archives) == 0) {
        //no archive exists - create a new canister

        let ?newArchive = await new_archive<system>({
          maxRecords = archiveState.settings.maxRecordsInArchiveInstance;
          indexType = archiveState.settings.archiveIndexType;
          maxPages = archiveState.settings.maxArchivePages;
          firstIndex = 0;
        }) else return;

        //set archive controllers calls async

        let newItem = {
          start = 0;
          length = 0;
        };

        ignore Map.put<Principal, T.TransactionRange>(mem.archives, Map.phash, Principal.fromActor(newArchive), newItem);
        ((Principal.fromActor(newArchive), newItem), archiveState.settings.maxRecordsInArchiveInstance);
      } else {
        // check that the last one isn't full;
        let lastArchive = switch (Map.peek(mem.archives)) {
          //"If the Map is not empty, returns the last (key, value) pair in the Map. Otherwise, returns null.""
          case (null) { Debug.trap("mem.archives unreachable") }; //unreachable;
          case (?val) val;
        };
        if (lastArchive.1.length >= archiveState.settings.maxRecordsInArchiveInstance) {
          // last archive is full, create a new archive

          let ?newArchive = await new_archive({
            maxRecords = archiveState.settings.maxRecordsInArchiveInstance;
            indexType = archiveState.settings.archiveIndexType;
            maxPages = archiveState.settings.maxArchivePages;
            firstIndex = lastArchive.1.start + lastArchive.1.length;
          }) else return;

          let newItem = {
            start = mem.firstIndex;
            length = 0;
          };
          ignore Map.put(mem.archives, Map.phash, Principal.fromActor(newArchive), newItem);
          ((Principal.fromActor(newArchive), newItem), archiveState.settings.maxRecordsInArchiveInstance);
        } else {
          //this is the case we reuse a previously/last create archive because there is free space
          let capacity = if (archiveState.settings.maxRecordsInArchiveInstance >= lastArchive.1.length) {
            Nat.sub(archiveState.settings.maxRecordsInArchiveInstance, lastArchive.1.length);
          } else {
            Debug.trap("max archive lenghth must be larger than the last archive length");
          };

          (lastArchive, capacity);
        };
      };

      let archive = actor (Principal.toText(archive_detail.0)) : T.ArchiveInterface;

      var archive_amount = if (history.len() > archiveState.settings.settleToRecords) {
        Nat.sub(history.len(), archiveState.settings.settleToRecords);
      } else {
        Debug.trap("Settle to records must be equal or smaller than the size of the ledger upon clanup");

      };

      // "bRbRecallAtEnd" is used to let know this function at the end, it still has work to do
      //  we could not archive all ledger records. so we need to update "archive_amount"

      var bRecallAtEnd = false;

      if (archive_amount > available_capacity) {
        bRecallAtEnd := true;
        archive_amount := available_capacity;
      };

      if (archive_amount > archiveState.settings.maxRecordsToArchive) {
        bRecallAtEnd := true;
        archive_amount := archiveState.settings.maxRecordsToArchive;
      };

      let length = Nat.min(history.len(), 1000);
      let end = history.end();
      let start = history.start();
      let resp_length = Nat.min(length, end - start);
      let toArchive = Vec.new<Transaction>();
      let transactions_array = Array.tabulate<T.Value>(
        resp_length,
        func(i) {
          let ?block = history.getOpt(start + i) else Debug.trap("Internal error");
          block;
        },
      );
      label find for (thisItem in Array.vals(transactions_array)) {
        Vec.add(toArchive, thisItem);
        if (Vec.size(toArchive) == archive_amount) break find;
      };

      // actually adding them

      try {
        let result = await archive.append_transactions(Vec.toArray(toArchive));
        let stats = switch (result) {
          case (#ok(stats)) stats;
          case (#Full(stats)) stats;
          case (#err(_)) {
            //do nothing...it failed;
            archiveState.bCleaning := false; //if error, we can desactivate bCleaning (set to True in the begining) and return (WHY!!!???)
            return;
          };
        };

        // remove those block already archived
        let archivedAmount = Vec.size(toArchive);
        // remove "archived_amount" blocks from the imnitial history
        history.deleteTo(mem.firstIndex + archivedAmount);
        mem.firstIndex := mem.firstIndex + archivedAmount;

        ignore Map.put(
          mem.archives,
          Map.phash,
          Principal.fromActor(archive),
          {
            start = archive_detail.1.start;
            length = archive_detail.1.length + archivedAmount;
          },
        );
      } catch (_) {
        //what do we do when it fails?  keep them in memory?
        archiveState.bCleaning := false;
        return;
      };

      // bCleaning :=false; to allow other timers to act
      // check bRecallAtEnd=True to make it possible to finish non archived transactions with a new timer

      archiveState.bCleaning := false;

      if (bRecallAtEnd) {
        archiveState.cleaningTimer := ?Timer.setTimer<system>(#seconds(0), check_clean_up);
      };

      return;
    };


    public func stats() : T.Stats {
      return {
        localLedgerSize = history.len(); 
        lastIndex = mem.lastIndex;
        firstIndex = mem.firstIndex;
        archives = Iter.toArray(Map.entries<Principal, T.TransactionRange>(mem.archives));
        ledgerCanister = mem.canister;
        bCleaning = archiveState.bCleaning;
        archiveProperties = archiveState.settings;
      };
    };



    public func get_blocks(args : T.GetBlocksArgs) : T.GetBlocksResult {
      let local_ledger_length = history.len();
      let ledger_length = if (mem.lastIndex == 0 and local_ledger_length == 0) {
        0;
      } else {
        mem.lastIndex; // + 1;
      };

      //get the transactions on this canister
      let transactions = Vec.new<T.ServiceBlock>();

      for (thisArg in args.vals()) {
        let start = if (thisArg.start + thisArg.length > mem.firstIndex) {

          let start = if (thisArg.start <= mem.firstIndex) {
            mem.firstIndex; //"our sliding window first valid element is archiveState.firstIndex not 0" 0;
          } else {
            if (thisArg.start >= (mem.firstIndex)) {
              thisArg.start; //"thisArg.start is already the index in our sliding window" Nat.sub(thisArg.start, (archiveState.firstIndex));
            } else {
              Debug.trap("last index must be larger than requested start plus one");
            };
          };

          let end = if (history.len() == 0) {
            // icdev: Vec.size(archiveState.ledger)==0){
            mem.lastIndex; //icdev: 0;
          } else if (thisArg.start + thisArg.length >= mem.lastIndex) {
            mem.lastIndex - 1 : Nat; //"lastIndex - 1 is sufficient to point the last available position in the sliding window) Nat.sub(archiveState.history.len(),1); // ILDE Vec.size(archiveState.ledger), 1);
          } else {
            thisArg.start + thisArg.length - 1 : Nat;
            //icdev: Nat.sub((Nat.sub(archiveState.lastIndex,archiveState.firstIndex)), (Nat.sub(archiveState.lastIndex, (thisArg.start + thisArg.length))))
          };

          // icdev: buf.getOpt(1) // -> ?"b"
          //some of the items are on this server
          if (history.len() > 0) {
            // icdev Vec.size(archiveState.ledger) > 0){
            label search for (thisItem in Iter.range(start, end)) {
              if (thisItem >= mem.lastIndex) {
                //icdev archiveState.history.len()){ //ILDE Vec.size(archiveState.ledger)){
                break search;
              };
              Vec.add(
                transactions,
                {
                  id = thisItem; //icdev: archiveState.firstIndex + thisItem;
                  block = history.getOpt(thisItem); //icdev: Vec.get(archiveState.ledger, thisItem)
                },
              );
            };
          };
        };
      };

      //get any relevant archives
      let archives = Map.new<Principal, (Vec.Vector<T.TransactionRange>, T.GetTransactionsFn)>();

      for (thisArgs in args.vals()) {
        if (thisArgs.start < mem.firstIndex) {

          var seeking = thisArgs.start;
          label archive for (thisItem in Map.entries(mem.archives)) {
            if (seeking > Nat.sub(thisItem.1.start + thisItem.1.length, 1) or thisArgs.start + thisArgs.length <= thisItem.1.start) {
              continue archive;
            };

            // Calculate the start and end indices of the intersection between the requested range and the current archive.
            let overlapStart = Nat.max(seeking, thisItem.1.start);
            let overlapEnd = Nat.min(thisArgs.start + thisArgs.length - 1, thisItem.1.start + thisItem.1.length - 1);
            let overlapLength = Nat.sub(overlapEnd, overlapStart) + 1;

            // Create an archive request for the overlapping range.
            switch (Map.get(archives, Map.phash, thisItem.0)) {
              case (null) {
                let newVec = Vec.new<T.TransactionRange>();
                Vec.add(
                  newVec,
                  {
                    start = overlapStart;
                    length = overlapLength;
                  },
                );
                let fn : T.GetTransactionsFn = (actor (Principal.toText(thisItem.0)) : T.ICRC3Interface).icrc3_get_blocks;
                ignore Map.put<Principal, (Vec.Vector<T.TransactionRange>, T.GetTransactionsFn)>(archives, Map.phash, thisItem.0, (newVec, fn));
              };
              case (?existing) {
                Vec.add(
                  existing.0,
                  {
                    start = overlapStart;
                    length = overlapLength;
                  },
                );
              };
            };

            // If the overlap ends exactly where the requested range ends, break out of the loop.
            if (overlapEnd == Nat.sub(thisArgs.start + thisArgs.length, 1)) {
              break archive;
            };

            // Update seeking to the next desired transaction.
            seeking := overlapEnd + 1;
          };
        };
      };

      return {
        log_length = ledger_length;
        certificate = CertifiedData.getCertificate(); //will be null in update calls
        blocks = Vec.toArray(transactions);
        archived_blocks = Iter.toArray<T.ArchivedTransactionResponse>(
          Iter.map<(Vec.Vector<T.TransactionRange>, T.GetTransactionsFn), T.ArchivedTransactionResponse>(
            Map.vals(archives),
            func(x : (Vec.Vector<T.TransactionRange>, T.GetTransactionsFn)) : T.ArchivedTransactionResponse {
              {
                args = Vec.toArray(x.0);
                callback = x.1;
              };
            },
          )
        );
      };
    };


    public func get_archives(request : T.GetArchivesArgs) : T.GetArchivesResult {

      let ?canister_aux = mem.canister else Debug.trap("Archive controller canister must be set before call get_archives");
       
      let results = Vec.new<T.GetArchivesResultItem>();

      var bFound = switch (request.from) {
        case (null) true;
        case (?Principal) false;
      };
      if (bFound == true) {
        Vec.add(
          results,
          {
            canister_id = canister_aux;
            start = mem.firstIndex;
            end = mem.lastIndex;
          },
        );
      } else {
        switch (request.from) {
          case (null) {}; //unreachable
          case (?val) {
            if (canister_aux == val) {
              bFound := true;
            };
          };
        };
      };

      for (thisItem in Map.entries<Principal, T.TransactionRange>(mem.archives)) {
        if (bFound == true) {
          if (thisItem.1.start + thisItem.1.length >= 1) {
            Vec.add(
              results,
              {
                canister_id = (thisItem.0);
                start = thisItem.1.start;
                end = Nat.sub(thisItem.1.start + thisItem.1.length, 1);
              },
            );
          } else {
            Debug.trap("found archive with length of 0");
          };
        } else {
          switch (request.from) {
            case (null) {}; //unreachable
            case (?val) {
              if (thisItem.0 == val) {
                bFound := true;
              };
            };
          };
        };
      };

      return Vec.toArray(results);
    };


    public func get_tip_certificate() : ?T.DataCertificate {

      let ct = CertTree.Ops(mem.cert_store);
      let blockWitness = ct.reveal([Text.encodeUtf8("last_block_index")]);
      let hashWitness = ct.reveal([Text.encodeUtf8("last_block_hash")]);
      let merge = MTree.merge(blockWitness, hashWitness);
      let witness = ct.encodeWitness(merge);
      return ?{
        certificate = switch (CertifiedData.getCertificate()) {
          case (null) {
            return null;
          };
          case (?val) val;
        };
        hash_tree = witness;
      };

    };

  };
};
