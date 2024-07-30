import Map "mo:map/Map";
import Principal "mo:base/Principal";
import ICRC "./ledger/icrc";
import U "./ledger/utils";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import SWB "mo:swbstable";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
//import Deduplication "./reducers/deduplication";
import Deduplication "./ledger/reducers/deduplication";
import T "./ledger/types";
//import Balances "reducers/balances";
import Balances "./ledger/reducers/balances";
import Sha256 "mo:sha2/Sha256";
//ILDE
import rechain "../src/lib";
import Vec "mo:vector";
import Nat64 "mo:base/Nat64";
import RepIndy "mo:rep-indy-hash";
import Timer "mo:base/Timer";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import Iter "mo:base/Iter";
import Text "mo:base/Text";

actor Self {

    // -- Ledger configuration
    let config : T.Config = {
        var TX_WINDOW  = 86400_000_000_000;  // 24 hours in nanoseconds
        var PERMITTED_DRIFT = 60_000_000_000;
        var FEE = 0;//1_000; ILDE: I make it 0 to simplify testing
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

    stable let chain_mem = rechain.Mem();


    // below methods are used to create block entries
    // I understand that block entry has following format:
    //    1) do touple ---> (value type object with ICRC3 schema compatible, phash of previous block according to ICRC3 standard)
    //    2) compute phash according to ICRC3 standard

    // Rechain dispatch code uses the below methods to compute the hash according to :
    //    1)NO  phash+1=hashBlock(encodeBlock(addHash(action_object, previous_hash=phash)))
    //    1)YES phash+1=hashBlock(addHash(encodeBlock~toGenericValue(action_object), previous_hash=phash)))

    // IMHERE--->How ICDev ICRC3 example is creating blocks?

    // public shared(msg) func testdecode(block: rechain.Value): async () {
    //     decodeBlock(block);
    // };
    // So to use Rechain, I think encodeBlock is just identity function, the hashblock is the standard

    func encodeBlock(b: T.Action) : rechain.Value {

        let trx = Vec.new<(Text, rechain.Value)>();
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

        let btype = switch (b.payload) {
            case (#burn(_)) {
                "1burn";
            };
            case (#transfer(_)) {
                "1xfer";
            };
            case (#mint(_)) {
                "1mint";
            };
            case (#transfer_from(_)) {
                "2xfer";
            };
        };
        Vec.add(trx, ("btype", #Text(btype)));

        // create a new "payload_trx = Vec.new<(Text, rechain.Value)>();"
        let payload_trx = switch (b.payload) {
            case (#burn(data)) {
                let inner_trx = Vec.new<(Text, rechain.Value)>();
                let amt: Nat = data.amt;
                Vec.add(inner_trx, ("amt", #Nat(amt)));
                let trx_from = Vec.new<rechain.Value>();
                for(thisItem in data.from.vals()){
                    Vec.add(trx_from,#Blob(thisItem));
                };
                let trx_from_array = Vec.toArray(trx_from);
                Vec.add(inner_trx, ("from", #Array(trx_from_array)));  
                let inner_trx_array = Vec.toArray(inner_trx);
                //Vec.add(trx, ("payload", #Map(inner_trx_array)));  
                inner_trx_array;     
            };
            case (#transfer(data)) {
                let inner_trx = Vec.new<(Text, rechain.Value)>();
                let amt: Nat = data.amt;
                Vec.add(inner_trx, ("amt", #Nat(amt)));
                let trx_from = Vec.new<rechain.Value>();
                for(thisItem in data.from.vals()){
                    Vec.add(trx_from,#Blob(thisItem));
                };
                let trx_from_array = Vec.toArray(trx_from);
                Vec.add(inner_trx, ("from", #Array(trx_from_array)));  
                let trx_to = Vec.new<rechain.Value>();
                for(thisItem in data.to.vals()){
                    Vec.add(trx_to,#Blob(thisItem));
                };
                let trx_to_array = Vec.toArray(trx_to);
                Vec.add(inner_trx, ("to", #Array(trx_to_array))); 
                let inner_trx_array = Vec.toArray(inner_trx);
                //Vec.add(trx, ("payload", #Map(inner_trx_array)));  
                inner_trx_array; 
            };
            case (#mint(data)) {
                let inner_trx = Vec.new<(Text, rechain.Value)>();
                let amt: Nat = data.amt;
                Vec.add(inner_trx, ("amt", #Nat(amt)));
                let trx_to = Vec.new<rechain.Value>();
                for(thisItem in data.to.vals()){
                    Vec.add(trx_to,#Blob(thisItem));
                };
                let trx_to_array = Vec.toArray(trx_to);
                Vec.add(inner_trx, ("to", #Array(trx_to_array)));  
                let inner_trx_array = Vec.toArray(inner_trx);
                //Vec.add(trx, ("payload", #Map(inner_trx_array)));  
                inner_trx_array; 
            };
            case (#transfer_from(data)) {
                let inner_trx = Vec.new<(Text, rechain.Value)>();
                let amt: Nat = data.amt;
                Vec.add(inner_trx, ("amt", #Nat(amt)));
                let trx_from = Vec.new<rechain.Value>();
                for(thisItem in data.from.vals()){
                    Vec.add(trx_from,#Blob(thisItem));
                };
                let trx_from_array = Vec.toArray(trx_from);
                Vec.add(inner_trx, ("from", #Array(trx_from_array)));  
                let trx_to = Vec.new<rechain.Value>();
                for(thisItem in data.to.vals()){
                    Vec.add(trx_to,#Blob(thisItem));
                };
                let trx_to_array = Vec.toArray(trx_to);
                Vec.add(inner_trx, ("to", #Array(trx_to_array))); 
                let inner_trx_array = Vec.toArray(inner_trx);
                inner_trx_array; 
            };
        };
        Vec.add(trx, ("payload", #Map(payload_trx))); 

        #Map(Vec.toArray(trx));
    };

    public type testtype = {
        #A: Int;
        #B: Text;
    };

    public shared(msg) func testme(): async testtype {
        return #A(2);
    };

    public shared(msg) func test1(): async rechain.Value {

        // ILDE: I need to set this manually 
        //chain.set_ledger_canister(Principal.fromActor(Self));

        let myin: T.Action = {
            ts = 3;
            created_at_time = null;
            fee = null;
            memo = null; 
            caller = let principal = Principal.fromText("un4fu-tqaaa-aaaab-qadjq-cai"); 
            payload = #burn({
                    amt=2;
                    from=[("0" : Blob)];
                });
        };
        encodeBlock(myin);        
    };

    public func test2(): async (Nat) {

        let mymint: T.Action = {
            ts = 3;
            created_at_time = null;
            fee = null;
            memo = null; 
            caller = let principal = Principal.fromText("un4fu-tqaaa-aaaab-qadjq-cai"); 
            payload = #mint({
                    amt=20000;
                    to=[("un4fu-tqaaa-aaaab-qadjq-cai":Blob),("0" : Blob)];
                });
        };

        let myin: T.Action = {
            ts = 3;
            created_at_time = null;
            fee = null;
            memo = null; 
            caller = let principal = Principal.fromText("un4fu-tqaaa-aaaab-qadjq-cai"); 
            payload = #burn({
                    amt=2;
                    from=[("un4fu-tqaaa-aaaab-qadjq-cai":Blob),("0" : Blob)];
                });
        };
        
        let a = add_record(mymint);

        let c = add_record(mymint);
    
        let b = add_record(myin);

        return 0;
                
    };
    
    public func test3(): async (Nat) {
        let mymint: T.Action = {
            ts = 3;
            created_at_time = null;
            fee = null;
            memo = null; 
            caller = let principal = Principal.fromText("un4fu-tqaaa-aaaab-qadjq-cai"); 
            payload = #mint({
                    amt=20000;
                    to=[("xuymj-7rdp2-s2yjx-efliz-piklp-hauai-2o5rs-gcfe4-4xay4-vzyfm-xqe":Blob),("0" : Blob)];
                });
        };
        let numTx:Nat = 60;

        for (i in Iter.range(0,  numTx- 1)) {
            let c = add_record(mymint);
        
        };

        0;
    };

    public query func compute_hash(auxm1: rechain.Value) : async ?Blob {
        let ret = ?Blob.fromArray(RepIndy.hash_val(auxm1));
        return ret;
    };

    public query func icrc3_get_blocks(args: rechain.GetBlocksArgs) : async rechain.GetBlocksResult{
        return chain.get_blocks(args);
    };

    public query func icrc3_get_archives(args: rechain.GetArchivesArgs) : async rechain.GetArchivesResult{
        return chain.get_archives(args);
    };

    var chain = rechain.Chain<T.Action, T.ActionError>({ 
        settings = ?{rechain.DEFAULT_SETTINGS with supportedBlocks = []; maxActiveRecords = 20; settleToRecords = 10; maxRecordsInArchiveInstance = 30;};
        mem = chain_mem;
        encodeBlock = encodeBlock;
        reducers = [balances.reducer];//, dedup.reducer];//, balancesIlde.reducer];  
    });

    public shared(msg) func check_archives_balance(): async () {
        return await chain.check_archives_balance();
    };

    ignore Timer.setTimer<system>(#seconds 0, func () : async () {
        Debug.print("inside setTimer");
        await chain.start_archiving<system>();
    });

    public shared(msg) func set_ledger_canister(): async () {
        chain_mem.canister := ?Principal.fromActor(Self);
        //chain.set_ledger_canister(Principal.fromActor(Self));
    };

    public shared(msg) func add_record(x: T.Action): async (DispatchResult) {
        //return icrc3().add_record<system>(x, null);

        let ret = chain.dispatch(x);  //handle error
        //add block to ledger

        return ret;


    };

    // ICRC-1
    public shared ({ caller }) func icrc1_transfer(req : ICRC.TransferArg) : async ICRC.Result {
        let ret = transfer(caller, req);
        ret;
    };

    public query func icrc1_balance_of(acc: ICRC.Account) : async Nat {
        balances.get(acc)
    };
 
    private func transfer(caller:Principal, req:ICRC.TransferArg) : ICRC.Result {
        let from : ICRC.Account = {
            owner = caller;
            subaccount = req.from_subaccount;
        };

        let payload = if (from == config.MINTING_ACCOUNT) {   
            let pri_blob: Blob = Principal.toBlob(req.to.owner);
            let aux = req.to.subaccount;
            let to_blob: [Blob] = switch aux {
                case (?Blob) [pri_blob, Blob];
                case (_) [pri_blob];
            };
            #mint({
                to = to_blob;
                amt = req.amount;
            });
        } else if (req.to == config.MINTING_ACCOUNT) {
            let from_blob: [Blob] = switch (req.from_subaccount) {
                case (?Blob) [Blob];
                case (_) [("0": Blob)];
            };
            #burn({
                from = from_blob;
                amt = req.amount;
            });
        } else if (false){
            let fee:Nat = switch(req.fee) {
                case (?Nat) Nat;
                case (_) 0:Nat;
            };
            let pri_blob: Blob = Principal.toBlob(req.to.owner);
            let aux = req.to.subaccount;
            let to_blob: [Blob] = switch aux {
                case (?Blob) [pri_blob, Blob];
                case (_) [pri_blob];
            };
            let from_blob: [Blob] = switch (req.from_subaccount) {
                case (?Blob) [Blob];
                case (_) [("0": Blob)];
            };
            #transfer_from({
                to = to_blob;
                from = from_blob;
                amt = req.amount;
            });
        } else {
            let fee:Nat = switch(req.fee) {
                case (?Nat) Nat;
                case (_) 0:Nat;
            };
            let pri_blob: Blob = Principal.toBlob(req.to.owner);
            let aux = req.to.subaccount;
            let to_blob: [Blob] = switch aux {
                case (?Blob) [pri_blob, Blob];
                case (_) [pri_blob];
            };
            let from_blob: [Blob] = switch (req.from_subaccount) {
                case (?Blob) [Blob];
                case (_) [("0": Blob)];
            };
            #transfer({
                to = to_blob;
                fee = fee;
                from = from_blob;
                amt = req.amount;
            });
        };

        let ts:Nat64 = switch (req.created_at_time) {
            case (?Nat64) Nat64;
            case (_) 0:Nat64;
        };

        let action = {
            caller = caller;
            ts = ts;
            created_at_time = req.created_at_time;
            memo = req.memo;
            fee = req.fee;
            payload = payload;
        };

        let ret = chain.dispatch(action);

        return ret;

    };

    public type DispatchResult = {#Ok : Nat;  #Err: T.ActionError };

    public func dispatch(actions: [T.Action]): async [DispatchResult] {
        Array.map(actions, func(x: T.Action): DispatchResult = chain.dispatch(x));
    };

};