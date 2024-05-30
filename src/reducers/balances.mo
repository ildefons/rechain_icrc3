import Map "mo:map/Map";
import Result "mo:base/Result";
import Sha256 "mo:sha2/Sha256";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Blob "mo:base/Blob";
import Chain "mo:rechain";
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

    public class Balances({ mem : Mem; config:T.Config }) {

        public func reducer(action : T.Action) : Chain.ReducerResponse<T.ActionError> {

            switch(action.payload) {
                case (#transfer(p)) {
                    ignore do ? { if (p.fee! != config.FEE) return #Err(#BadFee({ expected_fee = config.FEE })); };
                    let ?from_bacc = accountToBlob(p.from) else return #Err(#GenericError({ message = "Invalid From Subaccount"; error_code = 1111 }));
                    let ?to_bacc = accountToBlob(p.to) else return #Err(#GenericError({ message = "Invalid To Subaccount"; error_code = 1112 }));
                    let bal = get_balance(from_bacc);
                    let to_bal = get_balance(to_bacc);
                    if (bal < p.amount + config.FEE) return #Err(#InsufficientFunds({ balance = bal }));
                    #Ok(
                        func(_) {
                            put_balance(from_bacc, bal - p.amount - config.FEE);
                            put_balance(to_bacc, to_bal + p.amount);
                        }
                    );
                };
                case (#burn(p)) {
                    let ?from_bacc = accountToBlob(p.from) else return #Err(#GenericError({ message = "Invalid From Subaccount"; error_code = 1111 }));
                    let bal = get_balance(from_bacc);
                    if (bal < p.amount + config.FEE) return #Err(#BadBurn({ min_burn_amount = config.FEE }));
                    #Ok(
                        func(_) {
                            put_balance(from_bacc, bal - p.amount - config.FEE);
                        }
                    );
                };
                case (#mint(p)) {
                    let ?to_bacc = accountToBlob(p.to) else return #Err(#GenericError({ message = "Invalid To Subaccount"; error_code = 1112 }));
                    let to_bal = get_balance(to_bacc);
                    #Ok(
                        func(_) {
                            put_balance(to_bacc, to_bal - p.amount);
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
