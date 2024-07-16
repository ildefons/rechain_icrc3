import Map "mo:map/Map";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import SWB "mo:swb/Stable";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Sha256 "mo:sha2/Sha256";
import rechain  "../src/rechain";
import Vec "mo:vector";
import Nat64 "mo:base/Nat64";
import RepIndy "mo:rep-indy-hash";
import Timer "mo:base/Timer";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import Iter "mo:base/Iter";

actor Self {

    public type Action = {
        ts: Nat64;
        created_at_time: Nat64;
        memo: Blob;
        caller: Principal;
        fee: Nat;
        payload : {
            #swap: {
                amt: Nat;
            };
            #add: {
                amt : Nat;
            };
        };
    };

    public type ActionError = {ok:Nat; err:Text};

    stable let chain_mem  = rechain.Mem();

    func encodeBlock(b: Action): rechain.Value {

        let trx: rechain.Value  = #Map([
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

    func hashBlock(b: rechain.Value ): Blob {
        Blob.fromArray(RepIndy.hash_val(b));
    };

    public query func icrc3_get_blocks(args: rechain.GetBlocksArgs): async rechain.GetBlocksResult {
        return chain.get_blocks(args);
    };

    public query func icrc3_get_archives(args: rechain.GetArchivesArgs): async rechain.GetArchivesResult {
        return chain.get_archives(args);
    };

    public shared(msg) func set_ledger_canister(): async () {
        chain_mem.canister := ?Principal.fromActor(Self);
        //chain.set_ledger_canister(Principal.fromActor(Self));
    };

    var chain = rechain.Chain<Action, ActionError>({
        settings = {rechain.DEFAULT_SETTINGS with supportedBlocks = ["MYNEWBLOCK"]; maxActiveRecords = 100; settleToRecords = 30; maxRecordsInArchiveInstance = 120;};
        mem = chain_mem;
        encodeBlock = encodeBlock;
        addPhash = func(a, phash) = #Blob("0" : Blob);
        hashBlock = hashBlock;
        // reducers = [balances .reducer, dedup .reducer];//, balances .reducer];      //<-----REDO
        reducers = [];
    });


    public type DispatchResult = {#Ok: rechain.BlockId; #Err: ActionError };

    public shared(msg) func dispatch(actions: [Action]): async [DispatchResult] {
        Array.map(actions, func(x:Action): DispatchResult = chain.dispatch(x));
    };



};