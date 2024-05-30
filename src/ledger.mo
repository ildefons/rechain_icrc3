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
import T "./types";
import Balances "reducers/balances";
import Sha256 "mo:sha2/Sha256";

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

    //ILDEBegin
    public type Value = { 
        #Blob : Blob; 
        #Text : Text; 
        #Nat : Nat;
        #Int : Int;
        #Array : [Value]; 
        #Map : [(Text, Value)]; 
    };

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
   public type ActionIldeWithPhash = T.ActionIlde and { phash : Blob }; // adds a field at the top level

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

    public type ErrorIlde = {  //OK
        #GenericError : { message : Text; error_code : Nat };
        #TemporarilyUnavailable;
        #BadBurn : { min_burn_amount : Nat };
        #Duplicate : { duplicate_of : Nat };
        #BadFee : { expected_fee : Nat };
        #CreatedInFuture : { ledger_time : Nat64 };
        #TooOld;
        #InsufficientFunds : { balance : Nat };
    };
    
    //public type ActionWithPhash = Action and { phash : Blob };    // THIS IS NOIT CORRECT. I think this should be "type Value" == "ValueWithPhash"

    // -- Chain
    let chain_mem_ilde = Chain.Mem();

    // below methods are used to create block entries
    // I understand that block entry has following format:
    //    1) do touple ---> (value type object with ICRC3 schema compatible, phash of previous block according to ICRC3 standard)
    //    2) compute phash according to ICRC3 standard

    // Rechain dispatch code uses the below methods to compute the hash according to :
    //    1)NO  phash+1=hashBlock(encodeBlock(addHash(action_object, previous_hash=phash)))
    //    1)YES phash+1=hashBlock(addHash(encodeBlock~toGenericValue(action_object), previous_hash=phash)))

    // So to use Rechain, I think encodeBlock is just identity function, the hashblock is the standard

    

    let chain_ilde = Chain.Chain<T.ActionIlde, T.ActionError, T.ActionIldeWithPhash>({
        mem = chain_mem_ilde;
        encodeBlock = func(b) = ("myschemaid", to_candid (b)); // ERROR: this is innecessary. We need to retrieve blocks
                                                               // action.toGenericValue: I have to write it
                                                               // it converts the action to generic value!!!
                                                               // it converts to the action type to generic "value" type
                                                               // "to_candid" is different implementation in different languages
                                                               // instead  
                                                               // !!!! maybe the order of functions inside the dispatch of the rechain we need to re-order 
        addPhash = func(a, phash) = {a with phash};            // !!!! RROR because I type is wrong above?
        hashBlock = func(b) = Sha256.fromBlob(#sha224, b.1);   // NOT CORRECT: I should hash according to ICERC3 standard (copy/learn from ICDev)
        reducers = [dedup.reducer, balances.reducer];      //<-----REDO
    });

    public shared(msg) func add_record(x: T.ActionIlde): async Nat{
        //return icrc3().add_record<system>(x, null);

        //add block to ledger
        //chain_ilde.dispatch(x);  //handle error

        return 0;
    };

};
