import Map "mo:map/Map";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import SWB "mo:swb/Stable";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";

import T "./types";

import Sha256 "mo:sha2/Sha256";

import Vec "mo:vector";
import RepIndy "mo:rep-indy-hash";
import Text "mo:base/Text";
import Timer "mo:base/Timer";
import Archive "./archive";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import CertifiedData "mo:base/CertifiedData";
import Set "mo:map/Set";
import Iter "mo:base/Iter";
import Bool "mo:base/Bool";

module {
    public type Mem = {
        history : SWB.StableData<T.Value>;
        var phash : ?Blob;   // ILDE: I allow to be null in case of first block
        var lastIndex : Nat;
        var firstIndex : Nat;
        var canister: ?Principal;
        archives : Map.Map<Principal, T.TransactionRange>;
    };
    public func Mem() : Mem {
        {
            history = SWB.SlidingWindowBufferNewMem<T.Value>();
            var phash = null; //ILDE: before Blob.fromArray([0]);
            var lastIndex = 0; //ILDE
            var firstIndex = 0; //ILDE
            var canister = null; //ILDE
            archives = Map.new<Principal, T.TransactionRange>(); //ILDE
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

    /// ILDE: copied from ICDev ICRC3  Types implementation 
    /// The Interface for the Archive canister
    // public type ArchiveInterface = actor {
    //   /// Appends the given transactions to the archive.
    //   /// > Only the Ledger canister is allowed to call this method
    //   append_transactions : shared ([Transaction]) -> async AddTransactionsResponse;

    //   /// Returns the total number of transactions stored in the archive
    //   total_transactions : shared query () -> async Nat;

    //   /// Returns the transaction at the given index
    //   get_transaction : shared query (Nat) -> async ?Transaction;

    //   /// Returns the transactions in the given range
    //   icrc3_get_blocks : shared query (TransactionRange) -> async TransactionsResult;

    //   /// Returns the number of bytes left in the archive before it is full
    //   /// > The capacity of the archive canister is 32GB
    //   remaining_capacity : shared query () -> async Nat;
    // };
    public class Chain<A,E>({
        mem: Mem;
        //mem: Mem<A>;
        encodeBlock: (A) -> T.Value;   //ILDE: I changed B--->A 
        //addPhash: (A, phash: Blob) -> B;
        addPhash: (T.Value, phash: Blob) -> T.Value;
        //hashBlock: (Block) -> Blob;
        hashBlock: (T.Value) -> Blob;
        reducers : [ActionReducer<A,E>];
        args: ?T.InitArgs;
        }) {

        let history = SWB.SlidingWindowBuffer<T.Value>(mem.history);

        //ILDE: state variable (in the future I will join them all in a single variable "state"
        let state = {
            var canister: ?Principal = null; // ILDE: this is non-valid caniter controller until I set it up externally afater initialization 
                                              // ILDE: I have to add this paramter because it is used by "update_controllers"
            // var lastIndex = 0;
            // var firstIndex = 0;
            // var history = SWB.SlidingWindowBuffer<T.Value>(mem.history);
            // var phash: ?Blob = mem.phash;
            // var ledger : Vec.Vector<Transaction> = Vec.new<Transaction>(); //ILDE: not used
            var bCleaning = false; //ILDE: It indicates whether a archival process is on or not (only 1 possible at a time)
            var cleaningTimer: ?Nat = null; //ILDE: This timer will be set once we reach a ledger size > maxActiveRecords (see add_record mothod below)
            // var latest_hash = null; //ILDE: not used because I am using "phash" above 
            // supportedBlocks =  Vec.new<BlockType>(); //ILDE: not used
            // archives = Map.new<Principal, T.TransactionRange>();
            //ledgerCanister = caller;
            constants = {
                archiveProperties = switch(args){
                    case(_){
                        {
                        var maxActiveRecords = 100;//2000;    //ILDE: max size of ledger before archiving (state.history)
                        var settleToRecords = 30;//1000;        //ILDE: It makes sure to leave 1000 records in the ledger after archiving
                        var maxRecordsInArchiveInstance = 120;//10_000_000;    //ILDE: if archive full, we create a new one
                        var maxArchivePages  = 62500;      //ILDE: Archive constructor parameter: every page is 65536 per KiB. 62500 pages is default size (4 Gbytes)
                        var archiveIndexType = #Stable;
                        var maxRecordsToArchive = 10_000;  //ILDE: maximum number of blocks archived every archiving cycle. if bigger, a new time is started and the archiving function is called again
                        var archiveCycles = 2_000_000_000_000; //two trillion: cycle requirement to create an archive canister 
                        var archiveControllers = null;
                        };
                    };   // ILDE: TBD (requires adding "args" parameter to ildeChain constructor interface)
                    // case(?val){
                    //     {
                    //     var maxActiveRecords = val.maxActiveRecords;
                    //     var settleToRecords = val.settleToRecords;
                    //     var maxRecordsInArchiveInstance = val.maxRecordsInArchiveInstance;
                    //     var maxArchivePages  = val.maxArchivePages;
                    //     var archiveIndexType = val.archiveIndexType;
                    //     var maxRecordsToArchive = val.maxRecordsToArchive;
                    //     var archiveCycles = val.archiveCycles;
                    //     var archiveControllers = val.archiveControllers;   // ILDE: this is set to control archive canisters (plus the ledger canister), if this is null the canister controller becomes also the archive controller
                    //     };
                    // };
                };
            };
        };

        /// The IC actor used for updating archive controllers
        private let ic : T.IC = actor "aaaaa-aa";

        //let history = SWB.SlidingWindowBuffer<T.Value>(mem.history);
        public func print_archives() : () {
            Debug.print(debug_show(mem.archives));
        };
        
        // public func set_ledger_canister( canister: Principal ) : () {
        //     state.canister := ?canister;
        // };

        public func dispatch( action: A ) : ({#Ok : BlockId;  #Err: E }) {
            //ILDE: The way I serve the reducers does not change
            // Execute reducers
            let reducerResponse = Array.map<ActionReducer<A,E>, ReducerResponse<E>>(reducers, func (fn) = fn(action));
            // Check if any reducer returned an error and terminate if so
            let hasError = Array.find<ReducerResponse<E>>(reducerResponse, func (resp) = switch(resp) { case(#Err(_)) true; case(_) false; });
            //Debug.print("before checking for errors");
            switch(hasError) { case (?#Err(e)) { return #Err(e)};  case (_) (); };
            let blockId = mem.lastIndex + 1; //state.history.end() + 1; // ILDE: now state.lastIndex is the id of last block in the ledger 
            // Execute state changes if no errors
            ignore Array.map<ReducerResponse<E>, ()>(reducerResponse, func (resp) {let #Ok(f) = resp else return (); f(blockId);});
            // !!! ILDE:TBD

            Debug.print("dispatch went through!");

            // 1) translate A (ActionIlde: type from ledger project) to (Value: ICRC3 standard type defined in this same module)
            // 2) create new block according to steps 2-4 from ICDev ICRC3 implementation
            // 3) calculate and update "phash" according to step 5 from ICDev ICRC3 implementation
            // 4) add new block to ledger
            // 5... (TBD) management of archives

            // 1) translate A (ActionIlde: type from ledger project) to (Value: ICRC3 standard type defined in this same module)
            // "encodeBlock" is responsible for this transformation
            let encodedBlock: T.Value = encodeBlock(action);
            // 2) create new block according to steps 2-4 from ICDev ICRC3 implementation
            // creat enew empty block entry
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
            // covert vector to map to make it consistent with BlockIlde type
            let thisTrx = #Map(Vec.toArray(trx));
            // 3) calculate and update "phash" according to step 5 from ICDev ICRC3 implementation
            mem.phash := ?hashBlock(thisTrx);//?Blob.fromArray(RepIndy.hash_val(thisTrx));
            // 4) Add new block to ledger/history
            //Debug.print("History size before inside:" # Nat.toText(state.history.len()));
            ignore history.add(thisTrx);
            //ILDEbegin: One we add the block, we need to increase the lastIndex
            mem.lastIndex := mem.lastIndex + 1;
            //ILDEend
            //Debug.print("History size after inside:" # Nat.toText(state.history.len()));

            // code to create new archives

            //  1) Check whether is necessary to create a new archive
            //  2) If ne cessary, create timer with a period of 0 seconds to create it
            
            // if(Vec.size(state.ledger) > state.constants.archiveProperties.maxActiveRecords){
            if(history.len() > state.constants.archiveProperties.maxActiveRecords){
                switch(state.cleaningTimer){ 
                    case(null){ //only need one active timer
                        Debug.print("starting time because len: " # Nat.toText(history.len()));
                        state.cleaningTimer := ?Timer.setTimer(#seconds(0), check_clean_up);  //<--- IM HERE
                    };
                    case(_){
                        //Debug.print("Time is already set, so we don't create a new one");
                    };
                };
            };


            // let fblock = addPhash(action, state.phash);
            // let encodedBlock = encodeBlock(fblock);
            // ignore history.add(encodedBlock);
            // state.phash := hashBlock(encodedBlock);

            #Ok(blockId);
        };
        
        /// ILDE: This method is from ICDev ICRC3 implementation

        public func check_clean_up() : async (){

        // ILDE: preparation work: create an archive canister (start copying from ICDev)

        //clear the timer
            state.cleaningTimer := null;
            //Debug.print("Checking clean up Ilde");
            
        
        //ensure only one cleaning job is running
    
            if(state.bCleaning) {
                Debug.print("state.bCleaning");
                return; //only one cleaning at a time;
            };
            //Debug.print("Not currently Cleaning");
        
        //don't clean if not necessary
            //Debug.print("history.len(): "# Nat.toText(state.history.len()));
            //if(Vec.size(state.ledger) < state.constants.archiveProperties.maxActiveRecords) return;
            if(history.len() < state.constants.archiveProperties.maxActiveRecords) return;

        // ILDE: let know that we are creating an archive canister so noone else try at the same time

            state.bCleaning := true;
        
        //cleaning

            //Debug.print("Now we are cleaning");
            //Debug.print("Map.size(state.archives): "# Nat.toText(Map.size(state.archives)));

            let (archive_detail, available_capacity) = if(Map.size(mem.archives) == 0){ //ILDE: if first archive canister
                //no archive exists - create a new canister
                //add cycles;
                Debug.print("Creating a canister");

                if(ExperimentalCycles.balance() > state.constants.archiveProperties.archiveCycles * 2){
                    ExperimentalCycles.add(state.constants.archiveProperties.archiveCycles);
                } else{
                    //warning ledger will eventually overload
                    Debug.print("Not enough cycles" # debug_show(ExperimentalCycles.balance() ));
                    state.bCleaning := false;
                    return;
                };
                //commits state and creates archive
                Debug.print("aa1");
                let newArchive = await Archive.archive({
                        maxRecords = state.constants.archiveProperties.maxRecordsInArchiveInstance;
                        indexType = #Stable;
                        maxPages = state.constants.archiveProperties.maxArchivePages;
                        firstIndex = 0;
                }); 
                Debug.print("aa2");
                //set archive controllers calls async
                //ILDE: note that this method uses the costructor argument "canister" = princiapl of "ledger" canister
                //ignore //ILDE: since now "update_controllers" returns a possible error in case the ledger canister Principal is not yet set
                // ILDE: I added a await because I need to check that the ledger canister principal is well set 
                let myerror = await update_controllers(Principal.fromActor(newArchive));
                switch (myerror){
                    case(#err(val)){
                        Debug.print("aa3");
                        Debug.print("The ledger canister Principal is not yet. run setset_ledger_canister( canister: Principal ) and continue");
                        state.bCleaning := false;
                        return;
                    };
                    case(_){};
                };

                let newItem = {
                    start = 0;
                    length = 0;
                };

                //Debug.print("Have an archive");

                ignore Map.put<Principal, T.TransactionRange>(mem.archives, Map.phash, Principal.fromActor(newArchive),newItem);
                ((Principal.fromActor(newArchive), newItem), state.constants.archiveProperties.maxRecordsInArchiveInstance);
            } else{ 
                //check that the last one isn't full;
                Debug.print("Checking old archive");
                let lastArchive = switch(Map.peek(mem.archives)){    //ILDE: "If the Map is not empty, returns the last (key, value) pair in the Map. Otherwise, returns null.""
                    case(null) {Debug.trap("mem.archives unreachable")}; //unreachable;
                    case(?val) val;
                };
                Debug.print("else");
                if(lastArchive.1.length >= state.constants.archiveProperties.maxRecordsInArchiveInstance){ //ILDE: last archive is full, create a new archive
                    Debug.print("Need a new canister");
                    if(ExperimentalCycles.balance() > state.constants.archiveProperties.archiveCycles * 2){
                        ExperimentalCycles.add(state.constants.archiveProperties.archiveCycles);
                    } else{
                        //warning ledger will eventually overload
                        state.bCleaning := false;
                        return;
                    };
                    let newArchive = await Archive.archive({
                        maxRecords = state.constants.archiveProperties.maxRecordsInArchiveInstance;
                        indexType = #Stable;
                        maxPages = state.constants.archiveProperties.maxArchivePages;
                        firstIndex = lastArchive.1.start + lastArchive.1.length;
                    });
                    //ILDE state.firstIndex is update after this if/else archive creation
                    Debug.print("Have a multi archive");
                    let newItem = {
                        start = mem.firstIndex;
                        length = 0;
                    };
                    ignore Map.put(mem.archives, Map.phash, Principal.fromActor(newArchive), newItem);
                    ((Principal.fromActor(newArchive), newItem), state.constants.archiveProperties.maxRecordsInArchiveInstance);
                } else { //ILDE: this is the case we reuse a previously/last create archive because there is free space
                    Debug.print("just giving stats");
                    
                    let capacity = if(state.constants.archiveProperties.maxRecordsInArchiveInstance >= lastArchive.1.length){
                        Nat.sub(state.constants.archiveProperties.maxRecordsInArchiveInstance,  lastArchive.1.length);
                    } else {
                        Debug.trap("max archive lenghth must be larger than the last archive length");
                    };

                    (lastArchive, capacity);
                };
            };
        
         // ILDE: here the archive is created but it is still empty <------------
            Debug.print("b1");
         // ILDE: ie creates an archive instance accessible from this function
            let archive = actor(Principal.toText(archive_detail.0)) : T.ArchiveInterface;
         // ILDE: make sure that the amount of records to be archived is at least > than a constant "settleToRecords"

        // var archive_amount = if(Vec.size(state.ledger) > state.constants.archiveProperties.settleToRecords){
        //     Nat.sub(Vec.size(state.ledger), state.constants.archiveProperties.settleToRecords)

            Debug.print("b2,"#Nat.toText(history.len())#","#Nat.toText(state.constants.archiveProperties.settleToRecords));

            var archive_amount = if(history.len() > state.constants.archiveProperties.settleToRecords){
                Nat.sub(history.len(), state.constants.archiveProperties.settleToRecords)
            } else {
                Debug.trap("Settle to records must be equal or smaller than the size of the ledger upon clanup");

            };

            Debug.print("amount to archive is " # debug_show(archive_amount));

         // ILDE: "bRbRecallAtEnd" is used to let know this function at the end, it still has work to do 
         //       we could not archive all ledger records. so we need to update "archive_amount"

            var bRecallAtEnd = false;

            if(archive_amount > available_capacity){
                bRecallAtEnd := true;
                archive_amount := available_capacity;
            };

            if(archive_amount > state.constants.archiveProperties.maxRecordsToArchive){
                bRecallAtEnd := true;
                archive_amount := state.constants.archiveProperties.maxRecordsToArchive;
            };

            //Debug.print("amount to archive updated to " # debug_show(archive_amount));

         // ILDE: I had to create: "public type Transaction = T.Value;" and import ".\types" of rechain 

         // ILDE: moving trx from ledger to new archive canister

        //let toArchive = Vec.new<Transaction>();
        //label find for(thisItem in Vec.vals(state.ledger)){
        //     Vec.add(toArchive, thisItem);
        //     if(Vec.size(toArchive) == archive_amount) break find;
        // };
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
                case(#Full(stats)) stats;            //ILDE: full is not an error
                case(#err(_)){
                    //do nothing...it failed;
                    state.bCleaning := false;         //ILDE: if error, we can desactivate bCleaning (set to True in the begining) and return (WHY!!!???)
                    return;
                };
            };

         // ILDE: if everything goes well, 1) we create a new empty ledger
         //                                2) update firstIndex
         //                                3) update map of archives
         //                                4)

            // let new_ledger = Vec.new<Transaction>();
            // var tracker = 0;
            // let archivedAmount = Vec.size(toArchive);
            // for(thisItem in Vec.vals(state.ledger)){
            //     if(tracker >= archivedAmount){
            //         Vec.add(new_ledger, thisItem)
            //     };
            //     tracker += 1;
            // };
            //ILDE: just remove those block already archived
            let archivedAmount = Vec.size(toArchive);
            // remove "archived_amount" blocks from the imnitial history
            history.deleteTo(mem.firstIndex + archivedAmount);
            //ILDEend
            mem.firstIndex := mem.firstIndex + archivedAmount;
            //ILDE state.ledger := new_ledger;
            Debug.print("new ledger size " # debug_show(history.len()));
            
            ignore Map.put(mem.archives, Map.phash, Principal.fromActor(archive),{
                start = archive_detail.1.start;     
                length = archive_detail.1.length + archivedAmount;     
            })
        } catch (_){
                //what do we do when it fails?  keep them in memory?
                state.bCleaning := false;
                return;
        };

         // ILDE: bCleaning :=false; to allow other timers to act
         //       check bRecallAtEnd=True to make it possible to finish non archived transactions with a new timer

        state.bCleaning := false;

        if(bRecallAtEnd){
            state.cleaningTimer := ?Timer.setTimer(#seconds(0), check_clean_up);
        };

        return;
    };

    

    /// ILDE: code from ICDev
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
        //supportedBlocks = Iter.toArray<BlockType>(Vec.vals(state.supportedBlocks)); //ILDE: not used
        bCleaning = state.bCleaning;
        constants = {
          archiveProperties = {
            maxActiveRecords = state.constants.archiveProperties.maxActiveRecords;
            settleToRecords = state.constants.archiveProperties.settleToRecords;
            maxRecordsInArchiveInstance = state.constants.archiveProperties.maxRecordsInArchiveInstance;
            maxRecordsToArchive = state.constants.archiveProperties.maxRecordsToArchive;
            archiveCycles = state.constants.archiveProperties.archiveCycles;
            archiveControllers = state.constants.archiveProperties.archiveControllers;
          };
        };
      };
    };       

    /// ILDE: This method is from ICDev ICRC3 implementation
    /// ILDE: This method uses "canister" which is the princiapl of the main ledger actor
    /// ILDE: so, I have to pass "canister = Principal.fromActor(this)" from "ledger" to rechain 
    /// Updates the controllers for the given canister
    ///
    /// This function updates the controllers for the given canister.
    ///
    /// Arguments:
    /// - `canisterId`: The canister ID
    private func update_controllers(canisterId : Principal) : async (T.UpdatecontrollerResponse){ //<---HERE
        let ?canister = mem.canister else return #err(0);
        
        switch(state.constants.archiveProperties.archiveControllers){
            case(?val){
                let final_list = switch(val){
                    case(?list){
                        let a_set = Set.fromIter<Principal>(list.vals(), Map.phash);
                        Set.add(a_set, Map.phash, canister);
                        ?Set.toArray(a_set);
                    };
                    case(null){
                        ?[canister];
                    };
                };
                ignore ic.update_settings(({canister_id = canisterId; settings = {
                        controllers = final_list;
                        freezing_threshold = null;
                        memory_allocation = null;
                        compute_allocation = null;
                }}));
            };
            case(_){};    
        };

        return #ok(0);
    };

    // Handle transaction retrieval and archiving
    public func get_transactions(req: GetBlocksRequest) : GetTransactionsResponse {
        let length = Nat.min(req.length, 1000);
        let end = history.end();
        let start = history.start();
        let resp_length = Nat.min(length, end - start);
        let transactions = Array.tabulate<T.Value>(resp_length, func (i) {  
            let ?block = history.getOpt(start + i) else Debug.trap("Internal error");
            block;
            }); 

        {
            first_index=start;
            log_length=end;
            transactions;
            archived_transactions = [];
        };
    };

    /// ILDE: code from ICDev
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
        Debug.print("get_transaction_stats " # debug_show(stats()));
        let local_ledger_length = history.len(); //ILDE Vec.size(state.ledger);
        let ledger_length = if(mem.lastIndex == 0 and local_ledger_length == 0) {
            0;
        } else {
            mem.lastIndex + 1;
        };

        Debug.print("have ledger length " # debug_show(ledger_length));
        
        //get the transactions on this canister
        let transactions = Vec.new<T.ServiceBlock>();
        
        for(thisArg in args.vals()){
            Debug.print("print argument inside getBlocks");
            Debug.print(debug_show(thisArg));
            let start = if(thisArg.start + thisArg.length > mem.firstIndex){

                let start = if(thisArg.start <= mem.firstIndex){
                    mem.firstIndex;//ILDE:"our sliding window first valid element is state.firstIndex not 0" 0;
                } else{
                    if(thisArg.start >= (mem.firstIndex)){
                        thisArg.start;//ILDE:"thisArg.start is already the index in our sliding window" Nat.sub(thisArg.start, (state.firstIndex));
                    } else {
                        Debug.trap("last index must be larger than requested start plus one");
                    };
                };
                Debug.print("start: "# debug_show(start));
                
                let end = if(history.len()==0){ // ILDE Vec.size(state.ledger)==0){
                    mem.lastIndex;//ILDE: 0;
                } else if(thisArg.start + thisArg.length - 1 >= mem.lastIndex){
                    mem.lastIndex;//ILDE: "lastIndex is sufficient to point the last available position in the sliding window) Nat.sub(state.history.len(),1); // ILDE Vec.size(state.ledger), 1);
                } else {
                    thisArg.start + thisArg.length - 1;//ILDE
                    //ILDE Nat.sub((Nat.sub(state.lastIndex,state.firstIndex)), (Nat.sub(state.lastIndex, (thisArg.start + thisArg.length))))
                };

                Debug.print("getting local transactions" # debug_show(start,end)); // ILDE<-----
                // ILDE: buf.getOpt(1) // -> ?"b"
                //some of the items are on this server
                if(history.len() > 0 ){ // ILDE Vec.size(state.ledger) > 0){
                    label search for(thisItem in Iter.range(start, end)){
                        if(thisItem >= mem.lastIndex){ //ILDE state.history.len()){ //ILDE Vec.size(state.ledger)){
                            break search;
                        };
                        Vec.add(transactions, {
                            id = thisItem; //ILDE state.firstIndex + thisItem;
                            block = history.getOpt(thisItem); // ILDE Vec.get(state.ledger, thisItem)
                        });
                    };
                };
            };
        };

      //get any relevant archives
      let archives = Map.new<Principal, (Vec.Vector<T.TransactionRange>, T.GetTransactionsFn)>();

      for(thisArgs in args.vals()){
        if(thisArgs.start < mem.firstIndex){
          
          Debug.print("archive settings are " # debug_show(Iter.toArray(Map.entries(mem.archives))));
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

      Debug.print("returning transactions result" # debug_show(ledger_length, Vec.size(transactions), Map.size(archives)));
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

    /// ILDE: code from ICDev
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
      
      //ILDE: I introduce this conversion because the controller canister could be null if not set
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
  };
};