// import L "../src";
// import Principal "mo:base/Principal";
// import Blob "mo:base/Blob";
// import Float "mo:base/Float";
// import Int "mo:base/Int";
// import Iter "mo:base/Iter";
// import I "mo:itertools/Iter";
// import Nat8 "mo:base/Nat8";
// import Nat64 "mo:base/Nat64";
// import Debug "mo:base/Debug";

import Map "mo:map/Map";
import Principal "mo:base/Principal";
import ICRC "../src/icrc";
import U "../src/utils";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import SWB "mo:swb/Stable";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
//import Deduplication "./reducers/deduplication";
import DeduplicationIlde "../src/reducers/deduplicationIlde";
import T "../src/types";
//import Balances "reducers/balances";
import BalancesIlde "../src/reducers/balancesIlde";
import Sha256 "mo:sha2/Sha256";
//ILDE
import rechainIlde "../src/rechainIlde";
import Vec "mo:vector";
import Nat64 "mo:base/Nat64";
import RepIndy "mo:rep-indy-hash";
import Timer "mo:base/Timer";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import Iter "mo:base/Iter";

actor class({ledgerId: Principal}) = this {


    public func test() : async Nat { 
        return 5;
    };

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

    stable let chain_mem_ilde = rechainIlde.MemIlde();

    func encodeBlock(b: T.ActionIlde) : T.BlockIlde {

        let trx = Vec.new<(Text, T.BlockIlde)>();
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

        // create a new "payload_trx = Vec.new<(Text, rechainIlde.BlockIlde)>();"
        let payload_trx = switch (b.payload) {
            case (#burn(data)) {
                let inner_trx = Vec.new<(Text, T.BlockIlde)>();
                let amt: Nat = data.amt;
                Vec.add(inner_trx, ("amt", #Nat(amt)));
                let trx_from = Vec.new<T.BlockIlde>();
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
                let inner_trx = Vec.new<(Text, T.BlockIlde)>();
                let amt: Nat = data.amt;
                Vec.add(inner_trx, ("amt", #Nat(amt)));
                let trx_from = Vec.new<T.BlockIlde>();
                for(thisItem in data.from.vals()){
                    Vec.add(trx_from,#Blob(thisItem));
                };
                let trx_from_array = Vec.toArray(trx_from);
                Vec.add(inner_trx, ("from", #Array(trx_from_array)));  
                let trx_to = Vec.new<T.BlockIlde>();
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
                let inner_trx = Vec.new<(Text, T.BlockIlde)>();
                let amt: Nat = data.amt;
                Vec.add(inner_trx, ("amt", #Nat(amt)));
                let trx_to = Vec.new<T.BlockIlde>();
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
                let inner_trx = Vec.new<(Text, T.BlockIlde)>();
                let amt: Nat = data.amt;
                Vec.add(inner_trx, ("amt", #Nat(amt)));
                let trx_from = Vec.new<T.BlockIlde>();
                for(thisItem in data.from.vals()){
                    Vec.add(trx_from,#Blob(thisItem));
                };
                let trx_from_array = Vec.toArray(trx_from);
                Vec.add(inner_trx, ("from", #Array(trx_from_array)));  
                let trx_to = Vec.new<T.BlockIlde>();
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

    func hashBlock(b: T.BlockIlde) : Blob {
        Blob.fromArray(RepIndy.hash_val(b));
    };

    var chain_ilde = rechainIlde.ChainIlde<T.ActionIlde, T.ActionError, T.ActionIldeWithPhash>({ 
        args = null;
        mem = chain_mem_ilde;
        encodeBlock = encodeBlock;//func(b: T.ActionIlde) = #Blob("0" : Blob); //("myschemaid", to_candid (b)); // ERROR: this is innecessary. We need to retrieve blocks
                                                            // action.toGenericValue: I have to write it
                                                            // it converts the action to generic value!!!
                                                            // it converts to the action type to generic "value" type
                                                            // "to_candid" is different implementation in different languages
                                                            // instead  
                                                            // !!!! maybe the order of functions inside the dispatch of the rechain we need to re-order 
        addPhash = func(a, phash) = #Blob("0" : Blob); //{a with phash};            // !!!! RROR because I type is wrong above?
        hashBlock = hashBlock;//func(b) = Sha256.fromBlob(#sha224, "0" : Blob);//b.1);   // NOT CORRECT: I should hash according to ICERC3 standard (copy/learn from ICDev)
        reducers = [balancesIlde.reducer, dedupIlde.reducer];//, balancesIlde.reducer];      //<-----REDO
    });
    
    public query func icrc3_get_blocks(args: T.GetBlocksArgs) : async T.GetBlocksResult{
        return chain_ilde.get_blocks(args);
    };

    public query func icrc3_get_archives(args: T.GetArchivesArgs) : async T.GetArchivesResult{
        return chain_ilde.get_archives(args);
    };

    // // //public func test() : async Nat { 

    // public func set_ledger_canister(): async () {
    //     chain_mem_ilde.canister := ?Principal.fromActor(Self);
    //     //chain_ilde.set_ledger_canister(Principal.fromActor(Self));
    // };

    // public shared(msg) func add_record(x: T.ActionIlde): () {
    //     //return icrc3().add_record<system>(x, null);

    //     let ret = chain_ilde.dispatch(x);  //handle error
    //     //add block to ledger
    //     switch (ret) {
    //         case (#Ok(p)) {
    //             //Debug.print("Ok");
    //             //return p;
    //         };
    //         case (#Err(p)) {
    //             //<---I MHERE WHY????  Reducer BalcerIlde is giving error
    //             Debug.print("Error");
    //             //return 0;
    //         }
    //     }; 
    // };

    // // ICRC-1
    // public shared ({ caller }) func icrc1_transfer(req : ICRC.TransferArg) : async ICRC.Result {
    //     let ret = transfer(caller, req);
    //     ret;
    // };

    // public query func icrc1_balance_of(acc: ICRC.Account) : async Nat {
    //     balancesIlde.get(acc)
    // };

    // private func transfer(caller:Principal, req:ICRC.TransferArg) : ICRC.Result {
    //     let from : ICRC.Account = {
    //         owner = caller;
    //         subaccount = req.from_subaccount;
    //     };

    //     let payload = if (from == config.MINTING_ACCOUNT) {    // ILDE: repassar payload
    //         let pri_blob: Blob = Principal.toBlob(req.to.owner);
    //         let aux = req.to.subaccount;
    //         let to_blob: [Blob] = switch aux {
    //             case (?Blob) [pri_blob, Blob];
    //             case (_) [pri_blob];
    //         };
    //         #mint({
    //             to = to_blob;
    //             amt = req.amount;
    //         });
    //     } else if (req.to == config.MINTING_ACCOUNT) {
    //         let from_blob: [Blob] = switch (req.from_subaccount) {
    //             case (?Blob) [Blob];
    //             case (_) [("0": Blob)];
    //         };
    //         #burn({
    //             from = from_blob;
    //             amt = req.amount;
    //         });
    //     } else if (false){ //ILDE: This never happens is here to avoid return type error
    //         let fee:Nat = switch(req.fee) {
    //             case (?Nat) Nat;
    //             case (_) 0:Nat;
    //         };
    //         let pri_blob: Blob = Principal.toBlob(req.to.owner);
    //         let aux = req.to.subaccount;
    //         let to_blob: [Blob] = switch aux {
    //             case (?Blob) [pri_blob, Blob];
    //             case (_) [pri_blob];
    //         };
    //         let from_blob: [Blob] = switch (req.from_subaccount) {
    //             case (?Blob) [Blob];
    //             case (_) [("0": Blob)];
    //         };
    //         #transfer_from({
    //             to = to_blob;
    //             from = from_blob;
    //             amt = req.amount;
    //         });
    //     } else {
    //         let fee:Nat = switch(req.fee) {
    //             case (?Nat) Nat;
    //             case (_) 0:Nat;
    //         };
    //         let pri_blob: Blob = Principal.toBlob(req.to.owner);
    //         let aux = req.to.subaccount;
    //         let to_blob: [Blob] = switch aux {
    //             case (?Blob) [pri_blob, Blob];
    //             case (_) [pri_blob];
    //         };
    //         let from_blob: [Blob] = switch (req.from_subaccount) {
    //             case (?Blob) [Blob];
    //             case (_) [("0": Blob)];
    //         };
    //         #transfer({
    //             to = to_blob;
    //             fee = fee;
    //             from = from_blob;
    //             amt = req.amount;
    //         });
    //     };

    //     let ts:Nat64 = switch (req.created_at_time) {
    //         case (?Nat64) Nat64;
    //         case (_) 0:Nat64;
    //     };

    //     let action = {
    //         caller = caller;
    //         ts = ts;
    //         created_at_time = req.created_at_time;
    //         memo = req.memo;
    //         fee = req.fee;
    //         payload = payload;
    //     };

    //     let ret = chain_ilde.dispatch(action);
    //     return ret;

    // };

    // private func test_subaccount(n:Nat64) : ?Blob {
    //     ?Blob.fromArray(Iter.toArray(I.pad<Nat8>( Iter.fromArray(ENat64(n)), 32, 0 : Nat8)));
    // };

    // private func ENat64(value : Nat64) : [Nat8] {
    //     return [
    //         Nat8.fromNat(Nat64.toNat(value >> 56)),
    //         Nat8.fromNat(Nat64.toNat((value >> 48) & 255)),
    //         Nat8.fromNat(Nat64.toNat((value >> 40) & 255)),
    //         Nat8.fromNat(Nat64.toNat((value >> 32) & 255)),
    //         Nat8.fromNat(Nat64.toNat((value >> 24) & 255)),
    //         Nat8.fromNat(Nat64.toNat((value >> 16) & 255)),
    //         Nat8.fromNat(Nat64.toNat((value >> 8) & 255)),
    //         Nat8.fromNat(Nat64.toNat(value & 255)),
    //     ];
    // };


    // var next_subaccount_id:Nat64 = 100000;

    // stable let lmem = L.LMem();
    // let ledger = L.Ledger(lmem, Principal.toText(ledgerId), #last);
    
    // ledger.onMint(func (t) {
    //    // if sent mint transaction to this canister
    //    // we will split into 1,000 subaccounts
    //     var i = 0;
    //     label sending loop {
    //         let amount = t.amount / 10000; // Each account gets 1/10000
    //         ignore ledger.send({ to = {owner=ledger.me(); subaccount=test_subaccount(Nat64.fromNat(i))}; amount; from_subaccount = t.to.subaccount; });
    //         i += 1;
    //         if (i >= 1_000) break sending;
    //     }
    // });

    // let dust = 10000; // leave dust to try the balance of function

    // ledger.onReceive(func (t) {
    //     // if it has subaccount
    //     // we will pass half to another subaccount
    //     if (t.amount/10 < ledger.getFee() ) return; // if we send that it will be removed from our balance but won't register
    //     ignore ledger.send({ to = {owner=ledger.me(); subaccount=test_subaccount(next_subaccount_id)}; amount = t.amount / 10 ; from_subaccount = t.to.subaccount; });
    //     next_subaccount_id += 1;
    // });
    
    // ledger.start();
    // //---

    // public func start() {
    //     Debug.print("started");
    //     ledger.setOwner(this);
    //     };

    // public query func get_balance(s: ?Blob) : async Nat {
    //     ledger.balance(s)
    //     };

    // public query func get_errors() : async [Text] {
    //     ledger.getErrors();
    //     };

    // public query func get_info() : async L.Info {
    //     ledger.getInfo();
    //     };

    // public query func accounts() : async [(Blob, Nat)] {
    //     Iter.toArray(ledger.accounts());
    //     };

    // public query func getPending() : async Nat {
    //     ledger.getSender().getPendingCount();
    //     };
    
    // public query func ver() : async Nat {
    //     4
    //     };
    
    // public query func getMeta() : async L.Meta {
    //     ledger.getMeta()
    //     };
}