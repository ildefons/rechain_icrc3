import Map "mo:map/Map";
import Result "mo:base/Result";
import Sha256 "mo:sha2/Sha256";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Blob "mo:base/Blob";
//import Chain "mo:rechain";
import Chain "../rechainIlde";
import U "../utils";
import ICRC "../icrc";
import T "../types";

module {

    public type Mem = {
        accounts : Map.Map<Blob, Nat>;
    };

    public func Mem() : Mem = {
        accounts = Map.new<Blob, Nat>();
    };

    public class BalancesIlde({ mem : Mem; config:T.Config }) {   //<---

        public func reducer(action : T.ActionIlde) : Chain.ReducerResponse<T.ActionError> {

            switch(action.payload) {
                case (#transfer(p)) { // ICRC3 schema: btype = "1xfer"
                    //ILDEb
                    Debug.print("rb1");
                    let fee = switch (action.fee) {
                        case null 0;
                        case (?Nat) Nat;
                    }; 
                    //ILDEe    
                    ignore do ? { if (fee != config.FEE) return #Err(#BadFee({ expected_fee = config.FEE })); };
                    //let ?from_bacc = accountToBlob(p.from) else return #Err(#GenericError({ message = "Invalid From Subaccount"; error_code = 1111 }));
                    //ILDEb
                    let from_principal_blob = p.from[0];
                    let from_subaccount_blob = p.from[1];
                    let from_principal_principal = Principal.fromBlob(from_principal_blob);
                    let from_bacc = Principal.toLedgerAccount(from_principal_principal, ?from_subaccount_blob) 
                        else return #Err(#GenericError({ message = "Invalid From Subaccount"; error_code = 1111 }));
                    //ILDEe
                    //let ?to_bacc = accountToBlob(p.to) else return #Err(#GenericError({ message = "Invalid To Subaccount"; error_code = 1112 }));
                    //ILDEBegin
                    let to_principal_blob = p.to[0];
                    let to_subaccount_blob = p.to[1];
                    let to_principal_principal = Principal.fromBlob(to_principal_blob);
                    let to_bacc = Principal.toLedgerAccount(to_principal_principal, ?to_subaccount_blob) 
                        else return #Err(#GenericError({ message = "Invalid To Subaccount"; error_code = 1112 }));
                    //IlDEEnd                    
                    let bal = get_balance(from_bacc);
                    let to_bal = get_balance(to_bacc);
                    if (bal < p.amt + config.FEE) return #Err(#InsufficientFunds({ balance = bal }));
                    #Ok(
                        func(_) {
                            put_balance(from_bacc, bal - p.amt - config.FEE);
                            put_balance(to_bacc, to_bal + p.amt);
                        }
                    );
                };
                case (#transfer_from(p)) { // ICRC3 schema: btype = "2xfer"
                    //ILDE: TBD;
                    #Ok(func(_){});    //IMHERE
                };
                case (#burn(p)) {
                    //let ?from_bacc = accountToBlob(p.from) else return #Err(#GenericError({ message = "Invalid From Subaccount"; error_code = 1111 }));
                    //ILDEb
                    Debug.print("rbburn1");
                    let from_principal_blob = p.from[0];
                    Debug.print("rbburn11");
                    let from_subaccount_blob = p.from[1];
                    Debug.print("rbburn12");
                    let from_principal_principal = Principal.fromBlob(from_principal_blob);
                    Debug.print("rbburn13");
                    let from_bacc = Principal.toLedgerAccount(from_principal_principal, ?from_subaccount_blob) 
                        else return #Err(#GenericError({ message = "Invalid From Subaccount"; error_code = 1111 }));
                    //ILDEe
                    Debug.print("rbburn14");
                    let bal = get_balance(from_bacc);
                    Debug.print("rbburn15");
                    Debug.print(Nat.toText(p.amt));
                    Debug.print(Nat.toText(bal));
                    Debug.print(Nat.toText(config.FEE));
                    if (bal < p.amt + config.FEE) return #Err(#BadBurn({ min_burn_amount = config.FEE }));
                    #Ok(
                        func(_) {
                            put_balance(from_bacc, bal - p.amt - config.FEE);
                        }
                    );
                };
                case (#mint(p)) {
                    //let ?to_bacc = accountToBlob(p.to) else return #Err(#GenericError({ message = "Invalid To Subaccount"; error_code = 1112 }));
                    //ILDEBegin
                    let to_principal_blob = p.to[0];
                    let to_subaccount_blob = p.to[1];
                    let to_principal_principal = Principal.fromBlob(to_principal_blob);
                    let to_bacc = Principal.toLedgerAccount(to_principal_principal, ?to_subaccount_blob) 
                        else return #Err(#GenericError({ message = "Invalid To Subaccount"; error_code = 1112 }));
                    //IlDEEnd     
                    let to_bal = get_balance(to_bacc);
                    #Ok(
                        func(_) {
                            put_balance(to_bacc, to_bal + p.amt);
                        }
                    );
                }; 
            };

        };

        public func get(account: ICRC.Account) : Nat {
            let ?bacc = accountToBlob(account) else return 0;
            get_balance(bacc);
        };

        private func get_balance(bacc: Blob) : Nat {
            let ?bal = Map.get(mem.accounts, Map.bhash, bacc) else return 0;
            bal;
        };

        private func put_balance(bacc : Blob, bal : Nat) : () {
            ignore Map.put<Blob, Nat>(mem.accounts, Map.bhash, bacc, bal);
        };

        private func accountToBlob(acc: ICRC.Account) : ?Blob {
        ignore do ? { if (acc.subaccount!.size() != 32) return null; };
        ?Principal.toLedgerAccount(acc.owner, acc.subaccount);
    };
    };

};
