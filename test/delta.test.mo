import Map "mo:map/Map";
import Principal "mo:base/Principal";
import U "../src/utils";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import SWB "mo:swb/Stable";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import T "../src/types";
import Sha256 "mo:sha2/Sha256";
import rechainIlde "../src/rechainIlde";
import Vec "mo:vector";
import Nat64 "mo:base/Nat64";
import RepIndy "mo:rep-indy-hash";
import Timer "mo:base/Timer";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import Iter "mo:base/Iter";

actor Self {

    public type ActionIlde = {
        ts: Nat64;
        created_at_time: Nat64;
        memo: Blob;
        caller: Principal;
        fee: Nat;
        payload : {
            #swap : {
                amt: Nat;
            };
            #add : {
                amt : Nat;
            };
        };
    };

    public type ActionError = {ok:Nat; err:Text};

    stable let chain_mem_ilde = rechainIlde.MemIlde();

    func encodeBlock(b: ActionIlde) : rechainIlde.BlockIlde {

        let trx : T.BlockIlde = #Map([
            ("ts", #Nat(Nat64.toNat(b.ts))),
            ("created_at_time", #Nat(Nat64.toNat(b.created_at_time))),
            ("memo", #Blob(b.memo)),
            ("caller", #Blob(Principal.toBlob(b.caller))),
            ("fee", #Nat(b.fee)),
            ("btype", #Text(switch (b.payload) {
            case (#swap(_)) "1swap";
            case (#add(_)) "1add";
            })),
            ("payload", #Map(switch (b.payload) {
            case (#swap(data)) {
                [
                    ("amt", #Nat(data.amt))
                ]
            };
            case (#add(data)) {
                [
                    ("amt", #Nat(data.amt))
                ]
            };
            }))
        ]);

    };

    func hashBlock(b: rechainIlde.BlockIlde) : Blob {
        Blob.fromArray(RepIndy.hash_val(b));
    };

    
    public query func icrc3_get_blocks(args: T.GetBlocksArgs) : async T.GetBlocksResult{
        return chain_ilde.get_blocks(args);
    };

    public query func icrc3_get_archives(args: T.GetArchivesArgs) : async T.GetArchivesResult{
        return chain_ilde.get_archives(args);
    };

    var chain_ilde = rechainIlde.ChainIlde<ActionIlde, ActionError>({ 
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
        // reducers = [balancesIlde.reducer, dedupIlde.reducer];//, balancesIlde.reducer];      //<-----REDO
        reducers = [];
    });
    

    public shared(msg) func init(): () {
        chain_mem_ilde.canister := ?Principal.fromActor(Self);
    };

    public shared(msg) func add_record(x: ActionIlde): () {
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



};