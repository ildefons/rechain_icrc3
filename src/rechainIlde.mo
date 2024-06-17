import Map "mo:map/Map";
import Principal "mo:base/Principal";
import ICRC "./icrc";
import U "./utils";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import SWB "mo:swb/Stable";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
//import Chain "mo:rechain";
//import Deduplication "./reducers/deduplication";
//import DeduplicationIlde "./reducers/deduplicationIlde";
import T "./types";
//import Balances "reducers/balances";
//import BalancesIlde "reducers/balancesIlde";
import Sha256 "mo:sha2/Sha256";

//ILDE
import Vec "mo:vector";
import RepIndy "mo:rep-indy-hash";
import Text "mo:base/Text";
import Timer "mo:base/Timer";
import archiveIlde "./archiveIlde";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import Set "mo:map9/Set";

module {
    // public type BlockIlde = { 
    //     #Blob : Blob; 
    //     #Text : Text; 
    //     #Nat : Nat;
    //     #Int : Int;
    //     #Array : [BlockIlde]; 
    //     #Map : [(Text, BlockIlde)]; 
    // };
    public type MemIlde = {
        history : SWB.StableData<T.BlockIlde>;
        var phash : ?Blob;   // ILDE: I allow to be null in case of first block
    };
    public func MemIlde() : MemIlde {
        {
            history = SWB.SlidingWindowBufferNewMem<T.BlockIlde>();
            var phash = null; //ILDE: before Blob.fromArray([0]);
        }
    };
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
        transactions : [T.BlockIlde];
        archived_transactions : [ArchivedRange];
    };
    public type ArchivedRange = {
        callback : shared query GetBlocksRequest -> async TransactionRange;
        start : Nat;
        length : Nat;
    };
    //public type TransactionRange = { transactions : [T.BlockIlde] };
    public type TransactionRange = {
      start : Nat;
      length : Nat;
    };
    public type BlockType = {
        block_type : Text;
        url : Text;
    };
    public type Transaction = T.BlockIlde;
    public type AddTransactionsResponse = T.AddTransactionsResponse;
    public type TransactionsResult = T.TransactionsResult;

    /// ILDE: copied from ICDev ICRC3  Types implementation 
    /// The Interface for the Archive canister
    public type ArchiveInterface = actor {
      /// Appends the given transactions to the archive.
      /// > Only the Ledger canister is allowed to call this method
      append_transactions : shared ([Transaction]) -> async AddTransactionsResponse;

      /// Returns the total number of transactions stored in the archive
      total_transactions : shared query () -> async Nat;

      /// Returns the transaction at the given index
      get_transaction : shared query (Nat) -> async ?Transaction;

      /// Returns the transactions in the given range
      icrc3_get_blocks : shared query (TransactionRange) -> async TransactionsResult;

      /// Returns the number of bytes left in the archive before it is full
      /// > The capacity of the archive canister is 32GB
      remaining_capacity : shared query () -> async Nat;
    };
    public class ChainIlde<A,E,B>({
        mem: MemIlde;
        //mem: Mem<A>;
        encodeBlock: (A) -> T.BlockIlde;   //ILDE: I changed B--->A 
        //addPhash: (A, phash: Blob) -> B;
        addPhash: (T.BlockIlde, phash: Blob) -> T.BlockIlde;
        //hashBlock: (Block) -> Blob;
        hashBlock: (T.BlockIlde) -> Blob;
        reducers : [ActionReducer<A,T.ActionError>];
        args: ?T.InitArgs;
        }) {

        //ILDE: following vars and cts are mostly taken frm ICDev implementation
        let constants = {
            var maxActiveRecords = 2;//000;
            var settleToRecords = 1000;
            var maxRecordsInArchiveInstance = 10_000_000;
            var maxArchivePages  = 62500;
            var archiveIndexType = #Stable;
            var maxRecordsToArchive = 10_000;
            var archiveCycles = 2_000_000_000_000; //two trillion
            var archiveControllers = null;
        };

        //ILDE: state variable (in the future I will join them all in a single variable "state"
        let state = {
            var canister: ?Principal = null; // ILDE: this is non-valid caniter controller until I set it up externally afater initialization 
                                              // ILDE: I have to add this paramter because it is used by "update_controllers"
            var lastIndex = 0;
            var firstIndex = 0;
            var ledger : Vec.Vector<Transaction> = Vec.new<Transaction>();
            var bCleaning = false; //ILDE: It indicates whether a archival process is on or not (only 1 possible at a time)
            var cleaningTimer: ?Nat = null; //ILDE: This timer will be set once we reach a ledger size > maxActiveRecords (see add_record mothod below)
            var latest_hash = null;
            supportedBlocks =  Vec.new<BlockType>();
            archives = Map.new<Principal, TransactionRange>();
            //ledgerCanister = caller;
            constants = {
                archiveProperties = switch(args){
                    case(_){
                        {
                        var maxActiveRecords = 2;//000;
                        var settleToRecords = 1000;
                        var maxRecordsInArchiveInstance = 10_000_000;
                        var maxArchivePages  = 62500;
                        var archiveIndexType = #Stable;
                        var maxRecordsToArchive = 10_000;
                        var archiveCycles = 2_000_000_000_000; //two trillion
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

        let history = SWB.SlidingWindowBuffer<T.BlockIlde>(mem.history);

        public func set_ledger_canister( canister: Principal ) : () {
            state.canister := ?canister;
        };

        public func dispatch( action: A ) : ({#Ok : BlockId;  #Err: T.ActionError }) {
            //ILDE: The way I serve the reducers does not change
            Debug.print(Nat.toText(10));
            // Execute reducers
            let reducerResponse = Array.map<ActionReducer<A,T.ActionError>, ReducerResponse<T.ActionError>>(reducers, func (fn) = fn(action));
            Debug.print(Nat.toText(101));
            // Check if any reducer returned an error and terminate if so
            let hasError = Array.find<ReducerResponse<T.ActionError>>(reducerResponse, func (resp) = switch(resp) { case(#Err(_)) true; case(_) false; });
            switch(hasError) { case (?#Err(e)) { return #Err(e)};  case (_) (); };
            Debug.print(Nat.toText(102));
            let blockId = history.end() + 1;
            // Execute state changes if no errors
            ignore Array.map<ReducerResponse<T.ActionError>, ()>(reducerResponse, func (resp) {let #Ok(f) = resp else return (); f(blockId);});
            Debug.print(Nat.toText(103));
            // !!! ILDE:TBD

            // 1) translate A (ActionIlde: type from ledger project) to (BlockIlde: ICRC3 standard type defined in this same module)
            // 2) create new block according to steps 2-4 from ICDev ICRC3 implementation
            // 3) calculate and update "phash" according to step 5 from ICDev ICRC3 implementation
            // 4) add new block to ledger
            // 5... (TBD) management of archives

            // 1) translate A (ActionIlde: type from ledger project) to (BlockIlde: ICRC3 standard type defined in this same module)
            // "encodeBlock" is responsible for this transformation
            let encodedBlock: T.BlockIlde = encodeBlock(action);
            Debug.print(Nat.toText(104));
            // <---IMHERE
            // 2) create new block according to steps 2-4 from ICDev ICRC3 implementation
            // creat enew empty block entry
            let trx = Vec.new<(Text, T.BlockIlde)>();
            Debug.print(Nat.toText(105));
            // Add phash to empty block (null if not the first block)
            switch(mem.phash){
                case(null) {};
                case(?val){
                Vec.add(trx, ("phash", #Blob(val)));
                };
            };
            Debug.print(Nat.toText(106));
            // add encoded blockIlde to new block with phash
            Vec.add(trx,("tx", encodedBlock));
            Debug.print(Nat.toText(107));
            // covert vector to map to make it consistent with BlockIlde type
            let thisTrx = #Map(Vec.toArray(trx));
            Debug.print(Nat.toText(108));
            // 3) calculate and update "phash" according to step 5 from ICDev ICRC3 implementation
            mem.phash := ?hashBlock(thisTrx);//?Blob.fromArray(RepIndy.hash_val(thisTrx));
            Debug.print(Nat.toText(109));
            // 4) Add new block to ledger/history
            Debug.print(Nat.toText(1));
            Debug.print("History size before inside:" # Nat.toText(history.len()));
            ignore history.add(thisTrx);
            Debug.print("History size after inside:" # Nat.toText(history.len()));


            //IMHERE<-------
            // code to create new archives

            //  1) Check whether is necessary to create a new archive
            //  2) If ne cessary, create timer with a period of 0 seconds to create it
            // <---HOW TO KNOW IF NECESSARY???
            // if(Vec.size(state.ledger) > state.constants.archiveProperties.maxActiveRecords){
            Debug.print(Nat.toText(601));
            if(history.len() > constants.maxActiveRecords){
                switch(state.cleaningTimer){ 
                    case(null){ //only need one active timer
                        Debug.print(Nat.toText(602));
                        state.cleaningTimer := ?Timer.setTimer(#seconds(10), check_clean_up);  //<--- IM HERE
                    };
                    case(_){Debug.print(Nat.toText(603));};
                };
            };


            // let fblock = addPhash(action, mem.phash);
            // let encodedBlock = encodeBlock(fblock);
            // ignore history.add(encodedBlock);
            // mem.phash := hashBlock(encodedBlock);

            #Ok(blockId);
        };
        
        /// ILDE: This method is from ICDev ICRC3 implementation

        public func check_clean_up() : async (){

        // ILDE: preparation work: create an archive canister (start copying from ICDev)

        //clear the timer
            state.cleaningTimer := null;
            Debug.print("Checking clean up Ilde");
            
        
        //ensure only one cleaning job is running
    
            if(state.bCleaning) return; //only one cleaning at a time;
            Debug.print("Not currently Cleaning");
        
        //don't clean if not necessary
    
            //if(Vec.size(state.ledger) < state.constants.archiveProperties.maxActiveRecords) return;
            if(history.len() < state.constants.archiveProperties.maxActiveRecords) return;

        // ILDE: let know that we are creating an archive canister so noone else try at the same time

            state.bCleaning := true;
        
        //cleaning

            Debug.print("Now we are cleaning");

            let (archive_detail, available_capacity) = if(Map.size(state.archives) == 0){ //ILDE: if first archive canister
                //no archive exists - create a new canister
                //add cycles;
                Debug.print("Creating a canister");

                if(ExperimentalCycles.balance() > state.constants.archiveProperties.archiveCycles * 2){
                    ExperimentalCycles.add(state.constants.archiveProperties.archiveCycles);
                } else{
                    //warning ledger will eventually overload
                    Debug.print("Not enough cycles" # debug_show(ExperimentalCycles.balance() ));
                    state.bCleaning :=false;
                    return;
                };

                //commits state and creates archive
                let newArchive = await archiveIlde.archiveIlde({
                        maxRecords = state.constants.archiveProperties.maxRecordsInArchiveInstance;
                        indexType = #Stable;
                        maxPages = state.constants.archiveProperties.maxArchivePages;
                        firstIndex = 0;
                });
                //set archive controllers calls async
                //ILDE: note that this method uses the costructor argument "canister" = princiapl of "ledger" canister
                //ignore //ILDE: since now "update_controllers" returns a possible error in case the ledger canister Principal is not yet set
                // ILDE: I added a await because I need to check that the ledger canister principal is well set 
                let myerror = await update_controllers(Principal.fromActor(newArchive));
                switch (myerror){
                    case(#err(val)){
                        Debug.print("The ledger canister Principal is not yet. run setset_ledger_canister( canister: Principal ) and continue")
                    };
                    case(_){};
                };

                let newItem = {
                    start = 0;
                    length = 0;
                };

                Debug.print("Have an archive");

                ignore Map.put<Principal, TransactionRange>(state.archives, Map.phash, Principal.fromActor(newArchive),newItem);

                ((Principal.fromActor(newArchive), newItem), state.constants.archiveProperties.maxRecordsInArchiveInstance);
            } else{ 
                //check that the last one isn't full;
                Debug.print("Checking old archive");
                let lastArchive = switch(Map.peek(state.archives)){    //ILDE: "If the Map is not empty, returns the last (key, value) pair in the Map. Otherwise, returns null.""
                    case(null) {Debug.trap("state.archives unreachable")}; //unreachable;
                    case(?val) val;
                };
                
                if(lastArchive.1.length >= state.constants.archiveProperties.maxRecordsInArchiveInstance){ //ILDE: last archive is full, create a new archive
                    Debug.print("Need a new canister");
                    
                    if(ExperimentalCycles.balance() > state.constants.archiveProperties.archiveCycles * 2){
                        ExperimentalCycles.add(state.constants.archiveProperties.archiveCycles);
                    } else{
                        //warning ledger will eventually overload
                        state.bCleaning :=false;
                        return;
                    };

                    let newArchive = await archiveIlde.archiveIlde({
                        maxRecords = state.constants.archiveProperties.maxRecordsInArchiveInstance;
                        indexType = #Stable;
                        maxPages = state.constants.archiveProperties.maxArchivePages;
                        firstIndex = lastArchive.1.start + lastArchive.1.length;
                    });
                    //ILDE state.firstIndex is update after this if/else archive creation
                    Debug.print("Have a multi archive");
                    let newItem = {
                        start = state.firstIndex;
                        length = 0;
                    };
                    ignore Map.put(state.archives, Map.phash, Principal.fromActor(newArchive), newItem);
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

         // ILDE: ie creates an archive instance accessible from this function

            let archive = actor(Principal.toText(archive_detail.0)) : ArchiveInterface;
         
         // ILDE: make sure that the amount of records to be archived is at least > than a constant "settleToRecords"

        // var archive_amount = if(Vec.size(state.ledger) > state.constants.archiveProperties.settleToRecords){
        //     Nat.sub(Vec.size(state.ledger), state.constants.archiveProperties.settleToRecords)
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

            Debug.print("amount to archive updated to " # debug_show(archive_amount));

         // ILDE: "Transaction" is the old "Value" type which now is "BlockIlde" 
         //       so, I had to create: "public type Transaction = T.IldeBlock;" and import ".\types" of rechainIlde 

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
            let transactions_array = Array.tabulate<T.BlockIlde>(resp_length, func (i) {
                let ?block = history.getOpt(start + i) else Debug.trap("Internal error");
                block;
            }); 
            label find for(thisItem in Array.vals(transactions_array)){
                Vec.add(toArchive, thisItem);
                if(Vec.size(toArchive) == archive_amount) break find;
            };
        
            Debug.print("toArchive size " # debug_show(Vec.size(toArchive)));
        };

         // ILDE: actually adding them

    //         try{
    //             let result = await archive.append_transactions(Vec.toArray(toArchive));
    //             let stats = switch(result){
    //             case(#ok(stats)) stats;
    //             case(#Full(stats)) stats;            //ILDE: full is not an error
    //             case(#err(_)){
    //                 //do nothing...it failed;
    //                 state.bCleaning :=false;         //ILDE: if error, we can desactivate bCleaning (set to True in the begining) and return (WHY!!!???)
    //                 return;
    //             };
    //             };

         // ILDE: if everything goes well, 1) we create a new empty ledger
         //                                2) update firstIndex
         //                                3) update map of archives
         //                                4)

    //             let new_ledger = Vec.new<Transaction>();
    //             var tracker = 0;
    //             let archivedAmount = Vec.size(toArchive);
    //             for(thisItem in Vec.vals(state.ledger)){
    //             if(tracker >= archivedAmount){
    //                 Vec.add(new_ledger, thisItem)
    //             };
    //             tracker += 1;
    //             };
    //             state.firstIndex := state.firstIndex + archivedAmount;
    //             state.ledger := new_ledger;
    //             debug if(debug_channel.clean_up) D.print("new ledger size " # debug_show(Vec.size(state.ledger)));
    //             ignore Map.put(state.archives, Map.phash, Principal.fromActor(archive),{
    //             start = archive_detail.1.start;     // ILDE: unused?!
    //             length = archive_detail.1.length + archivedAmount;     // ILDE: unused?!
    //             })
    //         } catch (_){
    //             //what do we do when it fails?  keep them in memory?
    //             state.bCleaning :=false;
    //             return;
    //         };

         // ILDE: bCleaning :=false; to allow other timers to act
         //       check bRecallAtEnd=True to make it possible to finish non archived transactions with a new timer

    //         state.bCleaning :=false;

    //         if(bRecallAtEnd){
    //             state.cleaningTimer := ?Timer.setTimer<system>(#seconds(0), check_clean_up);
    //         };

    //         debug if(debug_channel.clean_up) D.print("Checking clean up" # debug_show(stats()));
    //         return;
    //         };



    // ILDE: this function is executed by the timer to create an archive and store the current ledger
    // Is very similar to the ICDev implementation:
    
    //     public func check_clean_up() : async (){
    //         //clear the timer
    //         Debug.print("Cleanins up");
    //         cleaningTimer := null;

    //         // copied from ICDev ICRC3 implementation
            
    //     };
        

        /// ILDE: This method is from ICDev ICRC3 implementation
        /// ILDE: This method uses "canister" which is the princiapl of the main ledger actor
        /// ILDE: so, I have to pass "canister = Principal.fromActor(this)" from "ledger" to rechainIlde 
        /// Updates the controllers for the given canister
        ///
        /// This function updates the controllers for the given canister.
        ///
        /// Arguments:
        /// - `canisterId`: The canister ID


        private func update_controllers(canisterId : Principal) : async (T.UpdatecontrollerResponse){ //<---HERE
            let canister = switch (state.canister) {
                case (?obj) {obj};
                case (_) { return #err(0) };
            };
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
            let transactions = Array.tabulate<T.BlockIlde>(resp_length, func (i) {  //ILDE NOTE "Block" ---> "BlockIlde"
                let ?block = history.getOpt(start + i) else Debug.trap("Internal error");
                block;
                }); 

            {
                first_index=start;
                log_length=end;
                transactions;
                archived_transactions = [];
            }
        };
    };
};