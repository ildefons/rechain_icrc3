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
    public type TransactionRange = { transactions : [T.BlockIlde] };

    public class ChainIlde<A,E,B>({
        mem: MemIlde;
        //mem: Mem<A>;
        encodeBlock: (A) -> T.BlockIlde;   //ILDE: I changed B--->A 
        //addPhash: (A, phash: Blob) -> B;
        addPhash: (T.BlockIlde, phash: Blob) -> T.BlockIlde;
        //hashBlock: (Block) -> Blob;
        hashBlock: (T.BlockIlde) -> Blob;
        reducers : [ActionReducer<A,T.ActionError>];
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
        var cleaningTimer:?Timer.TimerId = null;  //ILDE: This timer will be set once we reach a ledger size > maxActiveRecords (see add_record mothod below)

        let history = SWB.SlidingWindowBuffer<T.BlockIlde>(mem.history);

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
            if(history.len() > constants.maxActiveRecords){
                switch(cleaningTimer){
                    case(null){ //only need one active timer
            //         debug if(debug_channel.add_record) D.print("setting clean up timer");
                        cleaningTimer := ?Timer.setTimer(#seconds(10), check_clean_up);  //<--- IM HERE
                    };
                    case(_){};
                };
            };


            // let fblock = addPhash(action, mem.phash);
            // let encodedBlock = encodeBlock(fblock);
            // ignore history.add(encodedBlock);
            // mem.phash := hashBlock(encodedBlock);

            #Ok(blockId);
        };
        

        public func check_clean_up() : async (){

        // ILDE: preparation work: create an archive canister (start copying from ICDev)

        //clear the timer
            cleaningTimer := null;
            Debug.print("Checking clean up Ilde");
            ();
        };
        //ensure only one cleaning job is running
    
    //         if(state.bCleaning) return; //only one cleaning at a time;
    //         debug if(debug_channel.clean_up) D.print("Not currently Cleaning");

        //don't clean if not necessary
    //         if(Vec.size(state.ledger) < state.constants.archiveProperties.maxActiveRecords) return;

    //         state.bCleaning := true;

        //cleaning
    //         debug if(debug_channel.clean_up) D.print("Now we are cleaning");

    //         let (archive_detail, available_capacity) = if(Map.size(state.archives) == 0){
    //             //no archive exists - create a new canister
    //             //add cycles;
    //             debug if(debug_channel.clean_up) D.print("Creating a canister");

    //             if(ExperimentalCycles.balance() > state.constants.archiveProperties.archiveCycles * 2){
    //             ExperimentalCycles.add<system>(state.constants.archiveProperties.archiveCycles);
    //             } else{
    //             //warning ledger will eventually overload
    //             debug if(debug_channel.clean_up) D.print("Not enough cycles" # debug_show(ExperimentalCycles.balance() ));
    //                 state.bCleaning :=false;
    //             return;
    //             };

    //             //commits state and creates archive
    //             let newArchive = await Archive.Archive({
    //             maxRecords = state.constants.archiveProperties.maxRecordsInArchiveInstance;
    //             indexType = #Stable;
    //             maxPages = state.constants.archiveProperties.maxArchivePages;
    //             firstIndex = 0;
    //             });
    //             //set archive controllers calls async
    //             ignore update_controllers(Principal.fromActor(newArchive));

    //             let newItem = {
    //             start = 0;
    //             length = 0;
    //             };

    //             debug if(debug_channel.clean_up) D.print("Have an archive");

    //             ignore Map.put<Principal, TransactionRange>(state.archives, Map.phash, Principal.fromActor(newArchive),newItem);

    //             ((Principal.fromActor(newArchive), newItem), state.constants.archiveProperties.maxRecordsInArchiveInstance);
    //         } else{
    //             //check that the last one isn't full;
    //             debug if(debug_channel.clean_up) D.print("Checking old archive");
    //             let lastArchive = switch(Map.peek(state.archives)){
    //             case(null) {D.trap("unreachable")}; //unreachable;
    //             case(?val) val;
    //             };
                
    //             if(lastArchive.1.length >= state.constants.archiveProperties.maxRecordsInArchiveInstance){
    //             //this one is full, create a new archive
    //             debug if(debug_channel.clean_up) D.print("Need a new canister");
    //             if(ExperimentalCycles.balance() > state.constants.archiveProperties.archiveCycles * 2){
    //                 ExperimentalCycles.add<system>(state.constants.archiveProperties.archiveCycles);
    //             } else{
    //                 //warning ledger will eventually overload
    //                 state.bCleaning :=false;
    //                 return;
    //             };

    //             let newArchive = await Archive.Archive({
    //                 maxRecords = state.constants.archiveProperties.maxRecordsInArchiveInstance;
    //                 indexType = #Stable;
    //                 maxPages = state.constants.archiveProperties.maxArchivePages;
    //                 firstIndex = lastArchive.1.start + lastArchive.1.length;
    //             });

    //             debug if(debug_channel.clean_up) D.print("Have a multi archive");
    //             let newItem = {
    //                 start = state.firstIndex;
    //                 length = 0;
    //             };
    //             ignore Map.put(state.archives, Map.phash, Principal.fromActor(newArchive), newItem);
    //             ((Principal.fromActor(newArchive), newItem), state.constants.archiveProperties.maxRecordsInArchiveInstance);
    //             } else {
    //             debug if(debug_channel.clean_up) D.print("just giving stats");
                
    //             let capacity = if(state.constants.archiveProperties.maxRecordsInArchiveInstance >= lastArchive.1.length){
    //                 Nat.sub(state.constants.archiveProperties.maxRecordsInArchiveInstance,  lastArchive.1.length);
    //             } else {
    //                 D.trap("max archive lenghth must be larger than the last archive length");
    //             };

    //             (lastArchive, capacity);
    //             };
    //         };
         
         // ILDE: here the archive is created but it is still empty

         // ILDE: ie creates an archive instance accessible from this function

    //         let archive = actor(Principal.toText(archive_detail.0)) : MigrationTypes.Current.ArchiveInterface;
         
         // ILDE: make sure that the amount of records to be archived is at least > than a constant "settleToRecords"

    //         var archive_amount = if(Vec.size(state.ledger) > state.constants.archiveProperties.settleToRecords){
    //             Nat.sub(Vec.size(state.ledger), state.constants.archiveProperties.settleToRecords)
    //         } else {
    //             D.trap("Settle to records must be equal or smaller than the size of the ledger upon clanup");
    //         };

    //         debug if(debug_channel.clean_up) D.print("amount to archive is " # debug_show(archive_amount));

         // ILDE: "bRbRecallAtEnd" is used to let know this function at the end, it still has work to do 
         //       we could not archive all ledger records. so we need to update "archive_amount"

    //         var bRecallAtEnd = false;

    //         if(archive_amount > available_capacity){
    //             bRecallAtEnd := true;
    //             archive_amount := available_capacity;
    //         };

    //         if(archive_amount > state.constants.archiveProperties.maxRecordsToArchive){
    //             bRecallAtEnd := true;
    //             archive_amount := state.constants.archiveProperties.maxRecordsToArchive;
    //         };

    //         debug if(debug_channel.clean_up) D.print("amount to archive updated to " # debug_show(archive_amount));

         // ILDE: "Transaction" is the old "Value" type which now is "BlockIlde" 
         //       so, I need to create: "public type Transaction = T.IldeBlock;" and import ".\types" of rechainIlde 

         // ILDE: moving trx from ledger to new archive canister

    //         let toArchive = Vec.new<Transaction>();
    //         label find for(thisItem in Vec.vals(state.ledger)){
    //             Vec.add(toArchive, thisItem);
    //             if(Vec.size(toArchive) == archive_amount) break find;
    //         };

    //         debug if(debug_channel.clean_up) D.print("tArchive size " # debug_show(Vec.size(toArchive)));

         // ILDE: actually adding them

    //         try{
    //             let result = await archive.append_transactions(Vec.toArray(toArchive));
    //             let stats = switch(result){
    //             case(#ok(stats)) stats;
    //             case(#Full(stats)) stats;
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