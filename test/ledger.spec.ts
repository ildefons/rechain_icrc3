import { Principal } from "@dfinity/principal";
import { resolve } from "node:path";
import { Actor, PocketIc, createIdentity} from "@hadronous/pic";

import { IDL } from "@dfinity/candid";
import {
  _SERVICE as TestService,
  idlFactory as TestIdlFactory,
  init,
} from "./build/ledger.idl.js";

import {
  Action,
  Account,
  GetBlocksArgs,
  TransactionRange,
  GetTransactionsResult,
} from "./build/ledger.idl.js";


// ILDE import {ICRCLedgerService, ICRCLedger} from "./icrc_ledger/ledgerCanister";
//@ts-ignore
import { toState } from "@infu/icblast";
// Jest can't handle multi threaded BigInts o.O That's why we use toState

const WASM_PATH = resolve(__dirname, "./build/ledger.wasm");

export async function TestCan(pic: PocketIc, ledgerCanisterId: Principal) {
  const fixture = await pic.setupCanister<TestService>({
    idlFactory: TestIdlFactory,
    wasm: WASM_PATH,
    arg: IDL.encode(init({ IDL }), []), //{ ledgerId: ledgerCanisterId }
  });

  return fixture;
}

describe("Counter", () => {
  let pic: PocketIc;
  let can: Actor<TestService>;
  let canCanisterId: Principal;

  const jo = createIdentity('superSecretAlicePassword');
  const bob = createIdentity('superSecretBobPassword');
  const ilde = createIdentity('superSecretIldePassword');
  const john1 = createIdentity('superSecretJohn1Password');
  const john2 = createIdentity('superSecretJohn2Password');
  const john3 = createIdentity('superSecretJohn3Password');
  const john4 = createIdentity('superSecretJohn4Password');
  const john5 = createIdentity('superSecretJohn5Password');
  const john6 = createIdentity('superSecretJohn6Password');
  const john7 = createIdentity('superSecretJohn7Password');
  const john8 = createIdentity('superSecretJohn8Password');
  const john9 = createIdentity('superSecretJohn9Password');
  const john0 = createIdentity('superSecretJohn0Password');
  
  beforeAll(async () => {
    pic = await PocketIc.create(process.env.PIC_URL); //ILDE create();


    const fixture = await TestCan(pic, Principal.fromText("aaaaa-aa"));
    can = fixture.actor;
    canCanisterId = fixture.canisterId; //ILDE: I need the id given by
    
    await can.set_ledger_canister();
  });

  afterAll(async () => {
    await pic.tearDown(); //ILDE: this means "it removes the replica"
  });

  it("add_mint_record1", async () => {
    let my_action: Action = {
      ts : 0n,
      created_at_time : [0n], //?Nat64
      memo: [], //?Blob;
      caller: jo.getPrincipal(),  
      fee: [], //?Nat
      payload : {
          // #burn : {
          //     amt: Nat;
          //     from: [Blob];
          // };
          // #transfer : {
          //     to : [Blob];
          //     from : [Blob];
          //     amt : Nat;
          // };
          // #transfer_from : {
          //     to : [Blob];
          //     from : [Blob];
          //     amt : Nat;
          // };
          mint : {
              to : [ilde.getPrincipal().toUint8Array()],
              amt : 100n,
          },
      },
    };
    let r = await can.add_record(my_action);
    expect(r).toBe(0n);
  });

  it("add_mint_burn_check1", async () => {
    let my_mint_action: Action = {
      ts : 0n,
      created_at_time : [0n], //?Nat64
      memo: [], //?Blob;
      caller: jo.getPrincipal(),  
      fee: [], //?Nat
      payload : {
          mint : {
              to : [bob.getPrincipal().toUint8Array()],
              amt : 100n,
          },
      },
    };
    let my_burn_action: Action = {
      ts : 0n,
      created_at_time : [0n], //?Nat64
      memo: [], //?Blob;
      caller: jo.getPrincipal(),  
      fee: [], //?Nat
      payload : {
          burn : {
              amt : 50n,
              from : [bob.getPrincipal().toUint8Array()],
          },
      },
    };
    let r_mint = await can.add_record(my_mint_action);
    let r_burn = await can.add_record(my_burn_action);

    //{ owner : Principal; subaccount : ?Blob };
    let my_account: Account = {
      owner : bob.getPrincipal(),
      subaccount: [], 
    };
    let r_bal = await can.icrc1_balance_of(my_account);  

    expect(r_bal).toBe(50n);
  });

  it("trigger_archive1", async () => {
    let my_action: Action = {
      ts : 0n,
      created_at_time : [0n], //?Nat64
      memo: [], //?Blob;
      caller: jo.getPrincipal(),  
      fee: [], //?Nat
      payload : {
          mint : {
              to : [john1.getPrincipal().toUint8Array()],
              amt : 100n,
          },
      },
    };

    let i = 0n;
    for (; i < 5; i++) {
      let r = await can.add_record(my_action);
      console.log(i);
    }
    
    expect(i).toBe(5n);
  });

  it("retrieve_blocks1", async () => {
    //let tr: TransactionRange =  {start:10n,length:3n};
    let my_block_args: GetBlocksArgs = [
      {start:0n,length:3n},
      //{start:20n,length:3n},
    ]
    //   public type TransactionRange = {
    //     start : Nat;
    //     length : Nat;
    // };
    //   public type GetTransactionsResult = {
    //     // Total number of transactions in the
    //     // transaction log
    //     log_length : Nat;        
    //     blocks : [{ id : Nat; block : ?Value }];
    //     archived_blocks : [ArchivedTransactionResponse];
    // };
    let my_blocks:GetTransactionsResult = await can.icrc3_get_blocks(my_block_args);
    console.log("blocks");
    console.log(my_blocks.blocks[0]);
    expect(my_blocks.blocks.length).toBe(3);
  });

  // test content of blocks
  // test ids
  // test archived retrival of archived blocks
  // create many archives
  // do transfers and check balances

  async function passTime(n: number) {
    for (let i = 0; i < n; i++) {
      await pic.advanceTime(3 * 1000);
      await pic.tick(2);
    }
  }
});
