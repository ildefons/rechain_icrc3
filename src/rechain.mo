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
/*
  TODO important:
  1) O icrc3 certificates
  2) O motoko system capabilities + newest base library + newest motoko compilers
  3) O when creating new archive canister update controllers 
  4) remove all comments unless providing info
  5) remove Debug.print
  6) add icrc3 function for supportedBlocks

  7) Test scenario when archive canister is offline and we add transactions
  8) Test upgrade rechain user canister and check if memory persists
  9) Test for memory leak - adding 1mil records that result in insignificant or no state changes, and check if memory gets bloated. Memory should stay small

  Other:
  O Undestand how new packages are added to the project of we just do "npm run test": 1) build.sh rebuilds ".mops" because it does mops sources that looks for mops.toml
  Phash tests
  Timer of archive cretion from 0 to original 10 sec
  Test what happens if archive needs to be created when still previous one is being created
  Use archive index type
*/

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
    /// Represents the environment object passed to the ICRC3 class (cp from ICDev code)
    public type Environment = {
      updated_certification : ?((Blob, Nat) -> Bool); //called when a certification has been made
      get_certificate_store : ?(() -> CertTree.Store); //needed to pass certificate store to the class
    };
    public type Mem = {
        history : SWB.StableData<T.Value>;
        var phash : ?Blob;   
        var lastIndex : Nat;
        var firstIndex : Nat;
        var canister: ?Principal;
        archives : Map.Map<Principal, T.TransactionRange>;
        cert_store: CertTree.Store;
    };

    public func Mem() : Mem {
        {
            history = SWB.SlidingWindowBufferNewMem<T.Value>();
            var phash = null; 
            var lastIndex = 0; 
            var firstIndex = 0; 
            var canister = null; 
            archives = Map.new<Principal, T.TransactionRange>();
            cert_store = CertTree.newStore();//Certificate tree storage
        }
    };
    public type Value = T.Value;
    public type GetBlocksArgs = T.GetBlocksArgs;
    public type GetBlocksResult = T.GetBlocksResult;
    public type GetArchivesArgs = T.GetArchivesArgs;
    public type GetArchivesResult = T.GetArchivesResult;
    
    public type ActionReducer<A,B> = (A) -> ReducerResponse<B>;
    public type BlockId = Nat;
    public type ReducerResponse<E> = {
        #Ok: (BlockId) -> ();
        #Pass;
        #Err : E
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
          maxActiveRecords = 2000;    // max size of ledger before archiving (state.history)
          settleToRecords = 1000;        //It makes sure to leave 1000 records in the ledger after archiving
          maxRecordsInArchiveInstance = 10_000_000; //if archive full, we create a new one
          maxArchivePages  = 62500;      //Archive constructor parameter: every page is 65536 per KiB. 62500 pages is default size (4 Gbytes)
          archiveIndexType = #Stable;
          maxRecordsToArchive = 10_000;  // maximum number of blocks archived every archiving cycle. if bigger, a new time is started and the archiving function is called again
          archiveCycles = 2_000_000_000_000; //two trillion: cycle requirement to create an archive canister 
          archiveControllers = [];
          supportedBlocks = [];
        } : T.InitArgs;

    public class Chain<A,E>({
        mem: Mem;
        encodeBlock: (A) -> T.Value;   
        reducers : [ActionReducer<A,E>];
        settings: ?T.InitArgs;
        }) {

  

        let history = SWB.SlidingWindowBuffer<T.Value>(mem.history);

        let state = {
            var bCleaning = false; //It indicates whether a archival process is on or not (only 1 possible at a time)
            var cleaningTimer: ?Nat = null; //This timer will be set once we reach a ledger size > maxActiveRecords (see mothod below)
            constants = {
                archiveProperties = Option.get(settings, DEFAULT_SETTINGS);
            };
        };


        private func updated_certification(cert: Blob, lastIndex: Nat) : Bool{
          CertTree.Ops(mem.cert_store).setCertifiedData();
          return true;
        };
        private func get_certificate_store() : CertTree.Store {
          return mem.cert_store;
        };
        
        private func get_environment() : Environment{
          {
            updated_certification = ?updated_certification;
            get_certificate_store = ?get_certificate_store;
          };
        };

        public func print_archives() : () {
            Debug.print(debug_show(mem.archives));
        };

        public func dispatch<system>( action: A ) : ({#Ok : BlockId;  #Err: E }) {
            // Execute reducers
            let reducerResponse = Array.map<ActionReducer<A,E>, ReducerResponse<E>>(reducers, func (fn) = fn(action));
            // Check if any reducer returned an error and terminate if so
            let hasError = Array.find<ReducerResponse<E>>(reducerResponse, func (resp) = switch(resp) { case(#Err(_)) true; case(_) false; });

            switch(hasError) { case (?#Err(e)) { return #Err(e)};  case (_) (); };
            let blockId = mem.lastIndex + 1; //state.history.end() + 1; // ILDE: now state.lastIndex is the id of last block in the ledger 
            // Execute state changes if no errors
            ignore Array.map<ReducerResponse<E>, ()>(reducerResponse, func (resp) {let #Ok(f) = resp else return (); f(blockId);});

         
            if (state.constants.archiveProperties.archiveActive) {
              let encodedBlock: T.Value = encodeBlock(action);
              // create new empty block entry
              let trx = Vec.new<(Text, T.Value)>();
              // Add phash to empty block (null if not the first block)
              switch(mem.phash){
                  case(null) {};
                  case(?val){
                  Vec.add(trx, ("phash", #Blob(val)));
                  };
              };
              // add encoded blockIlde to new block with phash
              Vec.add(trx,("tx", encodedBlock));
              // covert vector to map to make it consistent with Value type
              let thisTrx = #Map(Vec.toArray(trx));
              mem.phash := ?Blob.fromArray(RepIndy.hash_val(thisTrx));
              ignore history.add(thisTrx);
              //One we add the block, we need to increase the lastIndex
              mem.lastIndex := mem.lastIndex + 1;

              if(history.len() > state.constants.archiveProperties.maxActiveRecords){
                  switch(state.cleaningTimer){ 
                      case(null){ //only need one active timer
                          state.cleaningTimer := ?Timer.setTimer<system>(#seconds(0), check_clean_up);  
                      };
                      case(_){
                      };
                  };
              };
              
              dispatch_cert();
            };

            #Ok(blockId);
        };
        
        public func upgrade_archives() : async () {

            for (archivePrincipal in Map.keys(mem.archives)) {
                let archiveActor = actor(Principal.toText(archivePrincipal)) : T.ArchiveInterface;
                let ArchiveMgr = (system Archive.archive)(#upgrade archiveActor);
                ignore await ArchiveMgr(null); // No change in settings
            }
        };

        private func new_archive<system>(initArg: T.ArchiveInitArgs) : async ?(actor {}) {
                Debug.print("New archive start");
                let ?this_canister = mem.canister else Debug.trap("No canister set");

                if(ExperimentalCycles.balance() > state.constants.archiveProperties.archiveCycles * 2){
                    ExperimentalCycles.add<system>(state.constants.archiveProperties.archiveCycles);
                } else {
                    //warning ledger will eventually overload
                    Debug.print("Not enough cycles" # debug_show(ExperimentalCycles.balance() ));
                    state.bCleaning := false;
                    return null;
                };

                let ArchiveMgr = (system Archive.archive)(#new {
                  settings = ?{
                    controllers = ?Array.append([this_canister], state.constants.archiveProperties.archiveControllers);
                    compute_allocation = null;
                    memory_allocation = null;
                    freezing_threshold = null;
                  }
                });

                try {
                    return ?(await ArchiveMgr(?initArg));
                } catch (err) {
                    state.bCleaning := false;
                    Debug.print("Error creating archive canister " # Error.message(err));
                    return null;
                };
                
                
        };

        private func dispatch_cert() : () {
          let env = get_environment();// else return;
          let ?latest_hash = mem.phash else return;
          let ?gcs = env.get_certificate_store else return;


          let ct = CertTree.Ops(gcs());
          ct.put([Text.encodeUtf8("last_block_index")], Utils.encodeBigEndian(mem.lastIndex));
          ct.put([Text.encodeUtf8("last_block_hash")], latest_hash);
          ct.setCertifiedData();
          
          let ?uc = env.updated_certification else return;

          ignore uc(latest_hash, mem.lastIndex);

        };

        /// This method is from ICDev ICRC3 implementation

        public func check_clean_up<system>() : async (){

            // preparation work: create an archive canister (start copying from ICDev)

            //clear the timer
            state.cleaningTimer := null;
            //Debug.print("Checking clean up Ilde");
            
        
            //ensure only one cleaning job is running
    
            if(state.bCleaning) {
                return; //only one cleaning at a time;
            };        
        
            if(history.len() < state.constants.archiveProperties.maxActiveRecords) return;

            // let know that we are creating an archive canister so noone else try at the same time

            state.bCleaning := true;
        
            //cleaning

            let (archive_detail, available_capacity) = if(Map.size(mem.archives) == 0){ 
                //no archive exists - create a new canister

                //commits state and creates archive
                Debug.print("New archive " # debug_show(state.constants.archiveProperties));

                let ?newArchive = await new_archive<system>({
                        maxRecords = state.constants.archiveProperties.maxRecordsInArchiveInstance;
                        indexType = state.constants.archiveProperties.archiveIndexType;
                        maxPages = state.constants.archiveProperties.maxArchivePages;
                        firstIndex = 0;
                }) else return;
                
                //set archive controllers calls async

                let newItem = {
                    start = 0;
                    length = 0;
                };

                ignore Map.put<Principal, T.TransactionRange>(mem.archives, Map.phash, Principal.fromActor(newArchive),newItem);
                ((Principal.fromActor(newArchive), newItem), state.constants.archiveProperties.maxRecordsInArchiveInstance);
            } else{ 
                //check that the last one isn't full;
                let lastArchive = switch(Map.peek(mem.archives)){    
                    //"If the Map is not empty, returns the last (key, value) pair in the Map. Otherwise, returns null.""
                    case(null) {Debug.trap("mem.archives unreachable")}; //unreachable;
                    case(?val) val;
                };
                //Debug.print("else");
                if(lastArchive.1.length >= state.constants.archiveProperties.maxRecordsInArchiveInstance){ //ILDE: last archive is full, create a new archive
                  //  Debug.print("Need a new canister");
              
                    let ?newArchive = await new_archive({
                        maxRecords = state.constants.archiveProperties.maxRecordsInArchiveInstance;
                        indexType = state.constants.archiveProperties.archiveIndexType;
                        maxPages = state.constants.archiveProperties.maxArchivePages;
                        firstIndex = lastArchive.1.start + lastArchive.1.length;
                    }) else return;
            
                    let newItem = {
                        start = mem.firstIndex;
                        length = 0;
                    };
                    ignore Map.put(mem.archives, Map.phash, Principal.fromActor(newArchive), newItem);
                    ((Principal.fromActor(newArchive), newItem), state.constants.archiveProperties.maxRecordsInArchiveInstance);
                } else { //this is the case we reuse a previously/last create archive because there is free space                    
                    let capacity = if(state.constants.archiveProperties.maxRecordsInArchiveInstance >= lastArchive.1.length){
                        Nat.sub(state.constants.archiveProperties.maxRecordsInArchiveInstance,  lastArchive.1.length);
                    } else {
                        Debug.trap("max archive lenghth must be larger than the last archive length");
                    };

                    (lastArchive, capacity);
                };
            };
        
            let archive = actor(Principal.toText(archive_detail.0)) : T.ArchiveInterface;

            var archive_amount = if(history.len() > state.constants.archiveProperties.settleToRecords){
                Nat.sub(history.len(), state.constants.archiveProperties.settleToRecords)
            } else {
                Debug.trap("Settle to records must be equal or smaller than the size of the ledger upon clanup");

            };

            // "bRbRecallAtEnd" is used to let know this function at the end, it still has work to do 
            //  we could not archive all ledger records. so we need to update "archive_amount"

            var bRecallAtEnd = false;

            if(archive_amount > available_capacity){
                bRecallAtEnd := true;
                archive_amount := available_capacity;
            };

            if(archive_amount > state.constants.archiveProperties.maxRecordsToArchive){
                bRecallAtEnd := true;
                archive_amount := state.constants.archiveProperties.maxRecordsToArchive;
            };

            let length = Nat.min(history.len(), 1000);
            let end = history.end();
            let start = history.start();
            let resp_length = Nat.min(length, end - start);
            let toArchive = Vec.new<Transaction>();
            let transactions_array = Array.tabulate<T.Value>(resp_length, func (i) {
                let ?block = history.getOpt(start + i) else Debug.trap("Internal error");
                block;
            }); 
            label find for(thisItem in Array.vals(transactions_array)){
                Vec.add(toArchive, thisItem);
                if(Vec.size(toArchive) == archive_amount) break find;
            };
        
         // ILDE: actually adding them

        try{
            let result = await archive.append_transactions(Vec.toArray(toArchive));
            let stats = switch(result){
                case(#ok(stats)) stats;
                case(#Full(stats)) stats;           
                case(#err(_)){
                    //do nothing...it failed;
                    state.bCleaning := false;  //if error, we can desactivate bCleaning (set to True in the begining) and return (WHY!!!???)
                    return;
                };
            };


            // remove those block already archived
            let archivedAmount = Vec.size(toArchive);
            // remove "archived_amount" blocks from the imnitial history
            history.deleteTo(mem.firstIndex + archivedAmount);
            mem.firstIndex := mem.firstIndex + archivedAmount;
            
            ignore Map.put(mem.archives, Map.phash, Principal.fromActor(archive),{
                start = archive_detail.1.start;     
                length = archive_detail.1.length + archivedAmount;     
            })
        } catch (_){
                //what do we do when it fails?  keep them in memory?
                state.bCleaning := false;
                return;
        };

         // bCleaning :=false; to allow other timers to act
         // check bRecallAtEnd=True to make it possible to finish non archived transactions with a new timer

        state.bCleaning := false;

        if(bRecallAtEnd){
            state.cleaningTimer := ?Timer.setTimer<system>(#seconds(0), check_clean_up);
        };

        return;
    };

    /// code from ICDev
    /// Returns the statistics of the migration
    ///
    /// This function returns the statistics of the migration.
    ///
    /// Returns:
    /// - The migration statistics
    public func stats() : T.Stats {
      return {
        localLedgerSize = history.len(); //ILDE: Vec.size(state.ledger);
        lastIndex = mem.lastIndex;
        firstIndex = mem.firstIndex;
        archives = Iter.toArray(Map.entries<Principal, T.TransactionRange>(mem.archives));
        ledgerCanister = mem.canister;
        
        bCleaning = state.bCleaning;
        archiveProperties = state.constants.archiveProperties;
       
      };
    };       
   
    /// code from ICDev
    /// Returns a set of transactions and pointers to archives if necessary
    ///
    /// This function returns a set of transactions and pointers to archives if necessary.
    ///
    /// Arguments:
    /// - `args`: The transaction range
    ///
    /// Returns:
    /// - The result of getting transactions
    
    public func get_blocks(args: T.GetBlocksArgs) : T.GetBlocksResult{
        let local_ledger_length = history.len(); //ILDE Vec.size(state.ledger);
        let ledger_length = if(mem.lastIndex == 0 and local_ledger_length == 0) {
            0;
        } else {
            mem.lastIndex;// + 1;
        };
        
        //get the transactions on this canister
        let transactions = Vec.new<T.ServiceBlock>();
        
        for(thisArg in args.vals()){
            let start = if(thisArg.start + thisArg.length > mem.firstIndex){

                let start = if(thisArg.start <= mem.firstIndex){
                    mem.firstIndex;//"our sliding window first valid element is state.firstIndex not 0" 0;
                } else{
                    if(thisArg.start >= (mem.firstIndex)){
                        thisArg.start;//"thisArg.start is already the index in our sliding window" Nat.sub(thisArg.start, (state.firstIndex));
                    } else {
                        Debug.trap("last index must be larger than requested start plus one");
                    };
                };
                                
                let end = if(history.len()==0){ // icdev: Vec.size(state.ledger)==0){
                    mem.lastIndex;//icdev: 0;
                } else if(thisArg.start + thisArg.length >= mem.lastIndex){
                    mem.lastIndex - 1:Nat;//"lastIndex - 1 is sufficient to point the last available position in the sliding window) Nat.sub(state.history.len(),1); // ILDE Vec.size(state.ledger), 1);
                } else {
                    thisArg.start + thisArg.length - 1:Nat;
                    //icdev: Nat.sub((Nat.sub(state.lastIndex,state.firstIndex)), (Nat.sub(state.lastIndex, (thisArg.start + thisArg.length))))
                };

                //Debug.print("getting local transactions" # debug_show(start,end)); 
                // icdev: buf.getOpt(1) // -> ?"b"
                //some of the items are on this server
                if(history.len() > 0 ){ // icdev Vec.size(state.ledger) > 0){
                    label search for(thisItem in Iter.range(start, end)){
                        if(thisItem >= mem.lastIndex){ //icdev state.history.len()){ //ILDE Vec.size(state.ledger)){
                            break search;
                        };
                        Vec.add(transactions, {
                            id = thisItem; //icdev: state.firstIndex + thisItem;
                            block = history.getOpt(thisItem); //icdev: Vec.get(state.ledger, thisItem)
                        });
                    };
                };
            };
        };

      //get any relevant archives
      let archives = Map.new<Principal, (Vec.Vector<T.TransactionRange>, T.GetTransactionsFn)>();

      for(thisArgs in args.vals()){
        if(thisArgs.start < mem.firstIndex){
          
          //Debug.print("archive settings are " # debug_show(Iter.toArray(Map.entries(mem.archives))));
          var seeking = thisArgs.start;
          label archive for(thisItem in Map.entries(mem.archives)){
            if (seeking > Nat.sub(thisItem.1.start + thisItem.1.length, 1) or thisArgs.start + thisArgs.length <= thisItem.1.start) {
                continue archive;
            };

            // Calculate the start and end indices of the intersection between the requested range and the current archive.
            let overlapStart = Nat.max(seeking, thisItem.1.start);
            let overlapEnd = Nat.min(thisArgs.start + thisArgs.length - 1, thisItem.1.start + thisItem.1.length - 1);
            let overlapLength = Nat.sub(overlapEnd, overlapStart) + 1;

            // Create an archive request for the overlapping range.
            switch(Map.get(archives, Map.phash, thisItem.0)){
              case(null){
                let newVec = Vec.new<T.TransactionRange>();
                Vec.add(newVec, {
                    start = overlapStart;
                    length = overlapLength;
                  });
                let fn  : T.GetTransactionsFn = (actor(Principal.toText(thisItem.0)) : T.ICRC3Interface).icrc3_get_blocks;
                ignore Map.put<Principal, (Vec.Vector<T.TransactionRange>, T.GetTransactionsFn)>(archives, Map.phash, thisItem.0, (newVec, fn));
              };
              case(?existing){
                Vec.add(existing.0, {
                  start = overlapStart;
                  length = overlapLength;
                });
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

      //build the result
      return {
        log_length = ledger_length;
        certificate = CertifiedData.getCertificate(); //will be null in update calls
        blocks = Vec.toArray(transactions);
        archived_blocks = Iter.toArray<T.ArchivedTransactionResponse>(Iter.map< (Vec.Vector<T.TransactionRange>, T.GetTransactionsFn), T.ArchivedTransactionResponse>(Map.vals(archives), func(x :(Vec.Vector<T.TransactionRange>, T.GetTransactionsFn)):  T.ArchivedTransactionResponse{
          {
            args = Vec.toArray(x.0);
            callback = x.1;
          }

        }));
      }
    };

    /// code from ICDev
    /// Returns the archive index for the ledger
    ///
    /// This function returns the archive index for the ledger.
    ///
    /// Arguments:
    /// - `request`: The archive request
    ///
    /// Returns:
    /// - The archive index
    public func get_archives(request: T.GetArchivesArgs) : T.GetArchivesResult {
      
      //I introduce this conversion because the controller canister could be null if not set
      let canister_aux: Principal = switch(mem.canister) {
        case null {Debug.trap("Archive controller canister must be set before call get_archives");};
        case (?Principal) Principal;
      };
      
      let results = Vec.new<T.GetArchivesResultItem>();
       
      var bFound = switch(request.from){  
        case(null) true;
        case(?Principal) false;
      };
      if(bFound == true){
          Vec.add(results,{
            canister_id = canister_aux; 
            start = mem.firstIndex;
            end = mem.lastIndex;
          });
        } else {
          switch(request.from){
            case(null) {}; //unreachable
            case(?val) {
              if(canister_aux == val){
                bFound := true;
              };
            };
          };
        };

      for(thisItem in Map.entries<Principal, T.TransactionRange>(mem.archives)){
        if(bFound == true){
          if(thisItem.1.start + thisItem.1.length >= 1){
            Vec.add(results,{
              canister_id = (thisItem.0);
              start = thisItem.1.start;
              end = Nat.sub(thisItem.1.start + thisItem.1.length, 1);
            });
          } else{
            Debug.trap("found archive with length of 0");
          };
        } else {
          switch(request.from){
            case(null) {}; //unreachable
            case(?val) {
              if(thisItem.0 == val){
                bFound := true;
              };
            };
          };
        };
      };

      return Vec.toArray(results);
    };

    /// from ICDev
    /// Returns the certificate for the ledger
    ///
    /// This function returns the certificate for the ledger.
    ///
    /// Returns:
    /// - The data certificate (nullable)

    public func get_tip_certificate() : ?T.DataCertificate { 
      let env = get_environment();// else return;
      
      switch(env.get_certificate_store){
        case(null){};
        case(?gcs){
          let ct = CertTree.Ops(gcs());
          let blockWitness = ct.reveal([Text.encodeUtf8("last_block_index")]);
          let hashWitness = ct.reveal([Text.encodeUtf8("last_block_hash")]);
          let merge = MTree.merge(blockWitness,hashWitness);
          let witness = ct.encodeWitness(merge);
          return ?{
            certificate = switch(CertifiedData.getCertificate()){
              case(null){
                return null;
              };
              case(?val) val;
            };
            hash_tree = witness;
          };
        };
      };
        
      
      return null;
    };


  };
};