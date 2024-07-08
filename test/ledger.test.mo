import Map "mo:map/Map";
import Principal "mo:base/Principal";
import ICRC "./ledger/icrc";
import U "./ledger/utils";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import SWB "mo:swb/Stable";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
//import Deduplication "./reducers/deduplication";
import Deduplication "./ledger/reducers/deduplication";
import T "./ledger/types";
//import Balances "reducers/balances";
import Balances "./ledger/reducers/balances";
import Sha256 "mo:sha2/Sha256";
//ILDE
import rechain "../src/rechain";
import Vec "mo:vector";
import Nat64 "mo:base/Nat64";
import RepIndy "mo:rep-indy-hash";
import Timer "mo:base/Timer";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import Iter "mo:base/Iter";

actor Self {

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

    stable let chain_mem = rechain.Mem();


    // below methods are used to create block entries
    // I understand that block entry has following format:
    //    1) do touple ---> (value type object with ICRC3 schema compatible, phash of previous block according to ICRC3 standard)
    //    2) compute phash according to ICRC3 standard

    // Rechain dispatch code uses the below methods to compute the hash according to :
    //    1)NO  phash+1=hashBlock(encodeBlock(addHash(action_object, previous_hash=phash)))
    //    1)YES phash+1=hashBlock(addHash(encodeBlock~toGenericValue(action_object), previous_hash=phash)))

    // IMHERE--->How ICDev ICRC3 example is creating blocks?

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

    func hashBlock(b: rechain.Value) : Blob {
        Blob.fromArray(RepIndy.hash_val(b));
    };

    public shared(msg) func test1(): async rechain.Value {

        // ILDE: I need to set this manually 
        //chain_ilde.set_ledger_canister(Principal.fromActor(Self));

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

        Debug.print("cycles:" # debug_show(ExperimentalCycles.balance() ));

        // ILDE: I need to set this manually 
        //chain_ilde.set_ledger_canister(Principal.fromActor(Self));

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

        // let aa: Nat = switch(a) {
        //     case (#Ok(pp)) pp;
        //     case (_) 0;
        // };

        let c = add_record(mymint);
        //Debug.print("History size before:"#Nat.toText(a));
        let b = add_record(myin);
        //Debug.print("History size before:"#Nat.toText(b));


        //var aux = Timer.setTimer(#seconds(5), check_clean_up); 


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
        
        Debug.print("Balance before:" # debug_show(ExperimentalCycles.balance() ));
        Debug.print("Cycles before:" # debug_show(ExperimentalCycles.available() ));
        for (i in Iter.range(0,  numTx- 1)) {
            let c = add_record(mymint);
            //Debug.print(Nat.toText(i));
        };
        Debug.print("Balance after:" # debug_show(ExperimentalCycles.balance() ));
        Debug.print("cycles:" # debug_show(ExperimentalCycles.available() ));
        
        chain_ilde.print_archives();

        0;
    };

    
    public query func icrc3_get_blocks(args: rechain.GetBlocksArgs) : async rechain.GetBlocksResult{
        return chain_ilde.get_blocks(args);
    };

    public query func icrc3_get_archives(args: rechain.GetArchivesArgs) : async rechain.GetArchivesResult{
        return chain_ilde.get_archives(args);
    };

    var chain_ilde = rechain.Chain<T.Action, T.ActionError>({ 
        args = null;
        mem = chain_mem;
        encodeBlock = encodeBlock;//func(b: T.Action) = #Blob("0" : Blob); //("myschemaid", to_candid (b)); // ERROR: this is innecessary. We need to retrieve blocks
                                                            // action.toGenericValue: I have to write it
                                                            // it converts the action to generic value!!!
                                                            // it converts to the action type to generic "value" type
                                                            // "to_candid" is different implementation in different languages
                                                            // instead  
                                                            // !!!! maybe the order of functions inside the dispatch of the rechain we need to re-order 
        addPhash = func(a, phash) = #Blob("0" : Blob); //{a with phash};            // !!!! RROR because I type is wrong above?
        hashBlock = hashBlock;//func(b) = Sha256.fromBlob(#sha224, "0" : Blob);//b.1);   // NOT CORRECT: I should hash according to ICERC3 standard (copy/learn from ICDev)
        reducers = [balances.reducer, dedup.reducer];//, balancesIlde.reducer];      //<-----REDO
    });
    

    public shared(msg) func set_ledger_canister(): async () {
        chain_mem.canister := ?Principal.fromActor(Self);
        //chain_ilde.set_ledger_canister(Principal.fromActor(Self));
    };

    public shared(msg) func add_record(x: T.Action): () {
        //return icrc3().add_record<system>(x, null);

        let ret = chain_ilde.dispatch(x);  //handle error
        //add block to ledger
        switch (ret) {
            case (#Ok(p)) {
                //Debug.print("Ok");
                //return p;
            };
            case (#Err(p)) {
                //<---I MHERE WHY????  Reducer BalcerIlde is giving error
                Debug.print("Error");
                //return 0;
            }
        }; 
    };

    // ICRC-1
    public shared ({ caller }) func icrc1_transfer(req : ICRC.TransferArg) : async ICRC.Result {
        let ret = transfer(caller, req);
        ret;
    };

    public query func icrc1_balance_of(acc: ICRC.Account) : async Nat {
        balances.get(acc)
    };

    // ILDE: TO BE DONE
    // Oversimplified ICRC-4
    // public shared({caller}) func batch_transfer(req: [ICRC.TransferArg]) : async [ICRC.Result] {
    //     Array.map<ICRC.TransferArg, ICRC.Result>(req, func (r) = transfer(caller, r));
    // };

    // ILDETO BE DONE!!!
    // ---->I understand I need a different get_transactions that is consistent with ICRC3 standard format
    // ----> So I need to convert motoko objects to ICRC3 blocks 
    // ----> It also says that "It also needs archival mechanism that spawns canisters, move blocks to them" (later)
    // . Alternative to ICRC-3 
    // public query func get_transactions(req: rechain.GetBlocksRequest) : async rechain.GetTransactionsResponse {
    //     chain_ilde.get_transactions(req);
    // };

    // --
  
    private func transfer(caller:Principal, req:ICRC.TransferArg) : ICRC.Result {
        let from : ICRC.Account = {
            owner = caller;
            subaccount = req.from_subaccount;
        };

        let payload = if (from == config.MINTING_ACCOUNT) {    // ILDE: repassar payload
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
        } else if (false){ //ILDE: This never happens is here to avoid return type error
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

        let ret = chain_ilde.dispatch(action);
        return ret;
        // switch (ret) {
        //     case (#Ok(p)) {
        //         Debug.print("Ok");
        //         ret;
        //     };
        //     case (#Err(p)) {
        //         //<---I MHERE WHY????  Reducer BalcerIlde is giving error
        //         Debug.print("Error");
        //         ret;
        //     }
        // }; 
    };

};