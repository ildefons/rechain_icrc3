import Map "mo:map/Map";
import Principal "mo:base/Principal";
import ICRC "./icrc";
import U "./utils";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import SWB "mo:swb/Stable";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Chain "mo:rechain";
import Deduplication "./reducers/deduplication";
import DeduplicationIlde "./reducers/deduplicationIlde";
import T "./types";
import Balances "reducers/balances";
import BalancesIlde "reducers/balancesIlde";
import Sha256 "mo:sha2/Sha256";

//ILDE
import Vec "mo:vector";
import RepIndy "mo:rep-indy-hash";

module {
    public type BlockIlde = { 
        #Blob : Blob; 
        #Text : Text; 
        #Nat : Nat;
        #Int : Int;
        #Array : [BlockIlde]; 
        #Map : [(Text, BlockIlde)]; 
    };
    public type MemIlde = {
        history : SWB.StableData<BlockIlde>;
        var phash : ?Blob;   // ILDE: I allow to be null in case of first block
    };
    public func MemIlde() : MemIlde {
        {
            history = SWB.SlidingWindowBufferNewMem<BlockIlde>();
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
        transactions : [BlockIlde];
        archived_transactions : [ArchivedRange];
    };
    public type ArchivedRange = {
        callback : shared query GetBlocksRequest -> async TransactionRange;
        start : Nat;
        length : Nat;
    };
    public type TransactionRange = { transactions : [BlockIlde] };

    public class ChainIlde<A,E,B>({
        mem: MemIlde;
        //mem: Mem<A>;
        encodeBlock: (A) -> BlockIlde;   //ILDE: I changed B--->A 
        //addPhash: (A, phash: Blob) -> B;
        addPhash: (BlockIlde, phash: Blob) -> BlockIlde;
        //hashBlock: (Block) -> Blob;
        hashBlock: (BlockIlde) -> Blob;
        reducers : [ActionReducer<A,E>];
        }) {// ---->IMHERE
        let history = SWB.SlidingWindowBuffer<BlockIlde>(mem.history);

        public func dispatch( action: A ) : {#Ok : BlockId;  #Err: E } {
            //ILDE: The way I serve the reducers does not change

            // Execute reducers
            let reducerResponse = Array.map<ActionReducer<A,E>, ReducerResponse<E>>(reducers, func (fn) = fn(action));

            // Check if any reducer returned an error and terminate if so
            let hasError = Array.find<ReducerResponse<E>>(reducerResponse, func (resp) = switch(resp) { case(#Err(_)) true; case(_) false; });
            switch(hasError) { case (?#Err(e)) { return #Err(e)};  case (_) (); };

            let blockId = history.end() + 1;
            // Execute state changes if no errors
            ignore Array.map<ReducerResponse<E>, ()>(reducerResponse, func (resp) {let #Ok(f) = resp else return (); f(blockId);});

            // !!! ILDE:TBD

            // 1) translate A (ActionIlde: type from ledger project) to (BlockIlde: ICRC3 standard type defined in this same module)
            // 2) create new block according to steps 2-4 from ICDev ICRC3 implementation
            // 3) calculate and update "phash" according to step 5 from ICDev ICRC3 implementation
            // 4) add new block to ledger
            // 5... (TBD) management of archives

            // 1) translate A (ActionIlde: type from ledger project) to (BlockIlde: ICRC3 standard type defined in this same module)
            // "encodeBlock" is responsible for this transformation
            let encodedBlock: BlockIlde = encodeBlock(action);

            // <---IMHERE
            // 2) create new block according to steps 2-4 from ICDev ICRC3 implementation
            // creat enew empty block entry
            let trx = Vec.new<(Text, BlockIlde)>();
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
            ignore history.add(thisTrx);

            // let fblock = addPhash(action, mem.phash);
            // let encodedBlock = encodeBlock(fblock);
            // ignore history.add(encodedBlock);
            // mem.phash := hashBlock(encodedBlock);

            #Ok(blockId);
        };

        // Handle transaction retrieval and archiving
        public func get_transactions(req: GetBlocksRequest) : GetTransactionsResponse {
            let length = Nat.min(req.length, 1000);
            let end = history.end();
            let start = history.start();
            let resp_length = Nat.min(length, end - start);
            let transactions = Array.tabulate<BlockIlde>(resp_length, func (i) {  //ILDE NOTE "Block" ---> "BlockIlde"
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