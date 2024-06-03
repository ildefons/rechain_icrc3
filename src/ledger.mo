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
import rechainIlde "./rechainIlde";
import Vec "mo:vector";
import Nat64 "mo:base/Nat64";

// module rechainIlde {
//     public type BlockIlde = { 
//         #Blob : Blob; 
//         #Text : Text; 
//         #Nat : Nat;
//         #Int : Int;
//         #Array : [BlockIlde]; 
//         #Map : [(Text, BlockIlde)]; 
//     };
//     public type MemIlde = {
//         history : SWB.StableData<BlockIlde>;
//         var phash : Blob;
//     };
//     public func MemIlde() : MemIlde {
//         {
//             history = SWB.SlidingWindowBufferNewMem<BlockIlde>();
//             var phash = Blob.fromArray([0]);
//         }
//     };
//     public type ActionReducer<A,B> = (A) -> ReducerResponse<B>;
//     public type BlockId = Nat;
//     public type ReducerResponse<E> = {
//         #Ok: (BlockId) -> ();
//         #Pass;
//         #Err : E
//     };
//     public type GetBlocksRequest = { start : Nat; length : Nat };
//     public type GetTransactionsResponse = {
//         first_index : Nat;
//         log_length : Nat;
//         transactions : [BlockIlde];
//         archived_transactions : [ArchivedRange];
//     };
//     public type ArchivedRange = {
//         callback : shared query GetBlocksRequest -> async TransactionRange;
//         start : Nat;
//         length : Nat;
//     };
//     public type TransactionRange = { transactions : [BlockIlde] };

//     public class ChainIlde<A,E,B>({
//         mem: MemIlde;
//         //mem: Mem<A>;
//         encodeBlock: (B) -> BlockIlde;
//         //addPhash: (A, phash: Blob) -> B;
//         addPhash: (BlockIlde, phash: Blob) -> BlockIlde;
//         //hashBlock: (Block) -> Blob;
//         hashBlock: (BlockIlde) -> Blob;
//         reducers : [ActionReducer<A,E>];
//         }) {// ---->IMHERE
//         let history = SWB.SlidingWindowBuffer<BlockIlde>(mem.history);

//         public func dispatch( action: A ) : {#Ok : BlockId;  #Err: E } {

//             // Execute reducers
//             let reducerResponse = Array.map<ActionReducer<A,E>, ReducerResponse<E>>(reducers, func (fn) = fn(action));

//             // Check if any reducer returned an error and terminate if so
//             let hasError = Array.find<ReducerResponse<E>>(reducerResponse, func (resp) = switch(resp) { case(#Err(_)) true; case(_) false; });
//             switch(hasError) { case (?#Err(e)) { return #Err(e)};  case (_) (); };

//             let blockId = history.end() + 1;
//             // Execute state changes if no errors
//             ignore Array.map<ReducerResponse<E>, ()>(reducerResponse, func (resp) {let #Ok(f) = resp else return (); f(blockId);});

//             // !!! ILDE:TBD

//             // Add block to history
//             // let fblock = addPhash(action, mem.phash);
//             // let encodedBlock = encodeBlock(fblock);
//             // ignore history.add(encodedBlock);
//             // mem.phash := hashBlock(encodedBlock);

//             #Ok(blockId);
//         };

//         // Handle transaction retrieval and archiving
//         public func get_transactions(req: GetBlocksRequest) : GetTransactionsResponse {
//             let length = Nat.min(req.length, 1000);
//             let end = history.end();
//             let start = history.start();
//             let resp_length = Nat.min(length, end - start);
//             let transactions = Array.tabulate<BlockIlde>(resp_length, func (i) {  //ILDE NOTE "Block" ---> "BlockIlde"
//                 let ?block = history.getOpt(start + i) else Debug.trap("Internal error");
//                 block;
//                 }); 

//             {
//                 first_index=start;
//                 log_length=end;
//                 transactions;
//                 archived_transactions = [];
//             }
//         };
//     };
// };

actor {

    // -- Ledger configuration
    let config : T.Config = {
        var TX_WINDOW  = 86400_000_000_000;  // 24 hours in nanoseconds
        var PERMITTED_DRIFT = 60_000_000_000;
        var FEE = 1_000;
        var MINTING_ACCOUNT = {
            owner = Principal.fromText("aaaaa-aa");
            subaccount = null;
            }
    };

    // -- Reducer : Balances
    stable let balances_mem = Balances.Mem();
    let balances = Balances.Balances({
        config;
        mem = balances_mem;
    });

    // -- Reducer : Deduplication

    stable let dedup_mem = Deduplication.Mem();
    let dedup = Deduplication.Deduplication({
        config;
        mem = dedup_mem;
    });

    // -- Chain
    let chain_mem = Chain.Mem();

    let chain = Chain.Chain<T.Action, T.ActionError, T.ActionWithPhash>({
        mem = chain_mem;
        encodeBlock = func(b) = ("myschemaid", to_candid (b));
        addPhash = func(a, phash) = {a with phash};
        hashBlock = func(b) = Sha256.fromBlob(#sha224, b.1);
        reducers = [dedup.reducer, balances.reducer];
    });

    // --

    // ICRC-1
    public shared ({ caller }) func icrc1_transfer(req : ICRC.TransferArg) : async ICRC.Result {
        transfer(caller, req);
    };

    public query func icrc1_balance_of(acc: ICRC.Account) : async Nat {
        balances.get(acc)
    };

    // Oversimplified ICRC-4
    public shared({caller}) func batch_transfer(req: [ICRC.TransferArg]) : async [ICRC.Result] {
        Array.map<ICRC.TransferArg, ICRC.Result>(req, func (r) = transfer(caller, r));
    };

    // ---->IMHERE: I understand I need a different get_transactions that is consistent with ICRC3 standard format
    // ----> So I need to convert motoko objects to ICRC3 blocks 
    // ----> It also says that "It also needs archival mechanism that spawns canisters, move blocks to them" (later)
    // . Alternative to ICRC-3 
    public query func get_transactions(req: Chain.GetBlocksRequest) : async Chain.GetTransactionsResponse {
        chain.get_transactions(req);
    };

    // --
  
    private func transfer(caller:Principal, req:ICRC.TransferArg) : ICRC.Result {
        let from : ICRC.Account = {
            owner = caller;
            subaccount = req.from_subaccount;
        };

        let payload : T.Payload = if (from == config.MINTING_ACCOUNT) {
            #mint({
                to = req.to;
                amount = req.amount;
            });
        } else if (req.to == config.MINTING_ACCOUNT) {
            #burn({
                from = from;
                amount = req.amount;
            });
        } else {
            #transfer({
                to = req.to;
                fee = req.fee;
                from = from;
                amount = req.amount;
            });
        };

        let action = {
            caller;
            created_at_time = req.created_at_time;
            memo = req.memo;
            timestamp = U.now();
            payload;
        };

        chain.dispatch(action);
    };

    // //ILDEBegin
    // public type Value = { 
    //     #Blob : Blob; 
    //     #Text : Text; 
    //     #Nat : Nat;
    //     #Int : Int;
    //     #Array : [Value]; 
    //     #Map : [(Text, Value)]; 
    // };

    // variant { Map = vec {
    // record { "btype"; "variant" { Text = "1mint" }};
    // record { "ts"; variant { Nat = 1_675_241_149_669_614_928 : nat } };
    // record { "tx"; variant { Map = vec {
    //     record { "amt"; variant { Nat = 100_000 : nat } };
    //     record { "to"; variant { Array = vec {
    //             variant { Blob = blob "Z\d0\ea\e8;\04*\c2CY\8b\delN\ea>]\ff\12^. WGj0\10\e4\02" };
    //     }}};
    //     }}};
    // }};

    //V, copied from "rechain_example"
    // public type Action = {
    //     ts: Nat;
    //     fee: ?Nat;
    //     payload : {
    //         #burn : {
    //             amt: Nat;
    //             to: [Blob];
    //         };
    //         #transfer : {
    //             to : [Blob];
    //             from : [Blob];
    //             amt : Nat;
    //         };
    //         #transfer_from : {
    //             to : [Blob];
    //             from : [Blob];
    //             amt : Nat;
    //         };
    //         #mint : {
    //             to : [Blob];
    //             amt : Nat;
    //         };
    //     };
    // };
   // public type ActionIldeWithPhash = T.ActionIlde and { phash : Blob }; // adds a field at the top level

//    public type Burn1 = { 
//         btype: Text;
//         ts: Nat;
//         tx: {
//             amt: Nat;
//             to: [Blob];
//         };
//     };
//     public type Burn2 = { 
//         btype: Text;
//         ts: Nat;
//         tx: {
//             amt: Nat;
//             to: [Blob];
//         };
//     };
//     public type ICRC3Type = {
//         #type1: Burn1;
//         #type2: Burn2;
//     };

   
    //public type ActionWithPhash = Action and { phash : Blob };    // THIS IS NOIT CORRECT. I think this should be "type Value" == "ValueWithPhash"

    //ILDE: modified version of rechain
    // public type BlockIlde = { 
    //     #Blob : Blob; 
    //     #Text : Text; 
    //     #Nat : Nat;
    //     #Int : Int;
    //     #Array : [BlockIlde]; 
    //     #Map : [(Text, BlockIlde)]; 
    // };
    // module{
    //     public type MemIlde = {
    //         history : SWB.StableData<BlockIlde>;
    //         var phash : Blob;
    //     };
    //     public func MemIlde() : MemIlde {
    //         {
    //             history = SWB.SlidingWindowBufferNewMem<BlockIlde>();
    //             var phash = Blob.fromArray([0]);
    //         }
    //     };
    // };
    // public type ActionReducer<A,B> = (A) -> ReducerResponse<B>;
    // public type BlockId = Nat;
    // public type ReducerResponse<E> = {
    //     #Ok: (BlockId) -> ();
    //     #Pass;
    //     #Err : E
    // };
    // public type GetBlocksRequest = { start : Nat; length : Nat };
    // public type GetTransactionsResponse = {
    //     first_index : Nat;
    //     log_length : Nat;
    //     transactions : [BlockIlde];
    //     archived_transactions : [ArchivedRange];
    // };
    // public type ArchivedRange = {
    //     callback : shared query GetBlocksRequest -> async TransactionRange;
    //     start : Nat;
    //     length : Nat;
    // };
    // public type TransactionRange = { transactions : [BlockIlde] };

    // public class ChainIlde<A,E,B>({
    //     mem: MemIlde;
    //     //mem: Mem<A>;
    //     encodeBlock: (B) -> BlockIlde;
    //     //addPhash: (A, phash: Blob) -> B;
    //     addPhash: (BlockIlde, phash: Blob) -> BlockIlde;
    //     //hashBlock: (Block) -> Blob;
    //     hashBlock: (BlockIlde) -> Blob;
    //     reducers : [ActionReducer<A,E>];
    //     }) {// ---->IMHERE
    //     let history = SWB.SlidingWindowBuffer<BlockIlde>(mem.history);

    //     public func dispatch( action: A ) : {#Ok : BlockId;  #Err: E } {

    //         // Execute reducers
    //         let reducerResponse = Array.map<ActionReducer<A,E>, ReducerResponse<E>>(reducers, func (fn) = fn(action));

    //         // Check if any reducer returned an error and terminate if so
    //         let hasError = Array.find<ReducerResponse<E>>(reducerResponse, func (resp) = switch(resp) { case(#Err(_)) true; case(_) false; });
    //         switch(hasError) { case (?#Err(e)) { return #Err(e)};  case (_) (); };

    //         let blockId = history.end() + 1;
    //         // Execute state changes if no errors
    //         ignore Array.map<ReducerResponse<E>, ()>(reducerResponse, func (resp) {let #Ok(f) = resp else return (); f(blockId);});

    //         // Add block to history
    //         let fblock = addPhash(action, mem.phash);
    //         let encodedBlock = encodeBlock(fblock);
    //         ignore history.add(encodedBlock);
    //         mem.phash := hashBlock(encodedBlock);

    //         #Ok(blockId);
    //     };

    //     // Handle transaction retrieval and archiving
    //     public func get_transactions(req: GetBlocksRequest) : GetTransactionsResponse {
    //         let length = Nat.min(req.length, 1000);
    //         let end = history.end();
    //         let start = history.start();
    //         let resp_length = Nat.min(length, end - start);
    //         let transactions = Array.tabulate<Block>(resp_length, func (i) {
    //             let ?block = history.getOpt(start + i) else Debug.trap("Internal error");
    //             block;
    //             }); 

    //         {
    //             first_index=start;
    //             log_length=end;
    //             transactions;
    //             archived_transactions = [];
    //         }
    //     };
    // };

    // -- Reducer : Balances
    stable let balances_ilde_mem = BalancesIlde.Mem();
    let balancesIlde = BalancesIlde.BalancesIlde({
        config;
        mem = balances_ilde_mem;
    });

    // -- Reducer : Deduplication

    stable let dedup_ilde_mem = DeduplicationIlde.Mem();
    let dedupIlde = DeduplicationIlde.DeduplicationIlde({
        config;
        mem = dedup_ilde_mem;
    });

    // -- Chain

    let chain_mem_ilde = rechainIlde.MemIlde();


    // below methods are used to create block entries
    // I understand that block entry has following format:
    //    1) do touple ---> (value type object with ICRC3 schema compatible, phash of previous block according to ICRC3 standard)
    //    2) compute phash according to ICRC3 standard

    // Rechain dispatch code uses the below methods to compute the hash according to :
    //    1)NO  phash+1=hashBlock(encodeBlock(addHash(action_object, previous_hash=phash)))
    //    1)YES phash+1=hashBlock(addHash(encodeBlock~toGenericValue(action_object), previous_hash=phash)))

    // IMHERE--->How ICDev ICRC3 example is creating blocks?

    // So to use Rechain, I think encodeBlock is just identity function, the hashblock is the standard

    func encodeBlock(b: T.ActionIlde) : rechainIlde.BlockIlde {
        // conersion T.ActionIlde) ---> rechainIlde.BlockIlde
        // public type ActionIlde = {
        //     ts: Nat64;
        //     created_at_time: ?Nat64; //ILDE: I have added after the discussion with V
        //     memo: ?Blob; //ILDE: I have added after the discussion with V
        //     caller: Principal;  //ILDE: I have added after the discussion with V 
        //     fee: ?Nat;
        //     payload : {
        //         #burn : {
        //             amt: Nat;
        //             from: [Blob];
        //         };
        //         #transfer : {
        //             to : [Blob];
        //             from : [Blob];
        //             amt : Nat;
        //         };
        //         #transfer_from : {
        //             to : [Blob];
        //             from : [Blob];
        //             amt : Nat;
        //         };
        //         #mint : {
        //             to : [Blob];
        //             amt : Nat;
        //         };
        //     };
        // };

        //  public type BlockIlde = { 
        //     #Blob : Blob; 
        //     #Text : Text; 
        //     #Nat : Nat;
        //     #Int : Int;
        //     #Array : [BlockIlde]; 
        //     #Map : [(Text, BlockIlde)]; 
        // };
        let trx = Vec.new<(Text, rechainIlde.BlockIlde)>();
        // ts: Nat64;
        Vec.add(trx, ("ts", #Nat(Nat64.toNat(b.ts))));
        // created_at_time: ?Nat64; 
        let created_at_time: Nat64 = switch (b.created_at_time) {
            case null 0;
            case (?Nat) Nat;
        };
        Vec.add(trx, ("created_at_time", #Nat(Nat64.toNat(created_at_time))));
        // memo: ?Blob; 
        let memo: Blob = switch (b.memo) {
            case null "0" : Blob;
            case (?Blob) Blob;
        };
        Vec.add(trx, ("memo", #Blob(memo)));
        // caller: Principal; 
        Vec.add(trx, ("caller", #Blob(Principal.toBlob(b.caller))));
        // fee: ?Nat;
        let fee: Nat = switch (b.fee) {
            case null 0;
            case (?Nat) Nat;
        };
        Vec.add(trx, ("fee", #Nat(fee)));

        // create a new "payload_trx = Vec.new<(Text, rechainIlde.BlockIlde)>();"
        // covert to #Map
        // add to trx
        // convert add to #Map

        #Blob("0" : Blob);
    };

    let chain_ilde = rechainIlde.ChainIlde<T.ActionIlde, T.ActionError, T.ActionIldeWithPhash>({  //ILDE: I think "T.ActionIldeWithPhash" is no lomger necessary
        mem = chain_mem_ilde;
        encodeBlock = encodeBlock;//func(b: T.ActionIlde) = #Blob("0" : Blob); //("myschemaid", to_candid (b)); // ERROR: this is innecessary. We need to retrieve blocks
                                                               // action.toGenericValue: I have to write it
                                                               // it converts the action to generic value!!!
                                                               // it converts to the action type to generic "value" type
                                                               // "to_candid" is different implementation in different languages
                                                               // instead  
                                                               // !!!! maybe the order of functions inside the dispatch of the rechain we need to re-order 
        addPhash = func(a, phash) = #Blob("0" : Blob); //{a with phash};            // !!!! RROR because I type is wrong above?
        hashBlock = func(b) = Sha256.fromBlob(#sha224, "0" : Blob);//b.1);   // NOT CORRECT: I should hash according to ICERC3 standard (copy/learn from ICDev)
        reducers = [dedupIlde.reducer, balancesIlde.reducer];      //<-----REDO
    });

    public shared(msg) func add_record(x: T.ActionIlde): async Nat {
        //return icrc3().add_record<system>(x, null);

        //add block to ledger
        let ret = chain_ilde.dispatch(x);  //handle error
        switch (ret) {
            case (#Ok(p)) return 0;
            case (#Err(p)) return 0;
        }; 
    };

};
