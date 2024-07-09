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
  Action 
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

  //ILDE
  // let account1 = "un4fu-tqaaa-aaaab-qadjq-cai";
  // let account2 = "xuymj-7rdp2-s2yjx-efliz-piklp";//-hauai-2o5rs-gcfe4-4xay4-vzyfm-xqe"
  // let account3 = "sickb-bnj44-s7f3g-xkdnm-j6jfj";//-kftdt-ykjrv-zxvd7-ygwd4-hvjzh-yae";
  // let account4 = "rfnyi-eycci-tvuyc-t6frr-e2zjb";//-v4ket-dolvt-z6i7m-s2off-vuccu-eqe";

  const jo = createIdentity('superSecretAlicePassword');
  const bob = createIdentity('superSecretBobPassword');
  const ilde = createIdentity('superSecretIldePassword');
  const john = createIdentity('superSecretJohnPassword');
  
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

  // it("test_mint_1_2", async () => {
    // <---- can.setIdentity(jo);"
    
  //   let r = await can.do_mint(account1, //caller_str <---- NO: use "can.setIdentity(jo);"
  //                             account2, //to_str
  //                             1000n, //amt_nat 
  //                             0n) //ts_nat
  //   expect(r).toBe(0n);
  // });

  // it("test_burn_1_2", async () => {
  //   let r = await can.do_burn(account1, //caller_str 
  //                             account2, //to_str
  //                             100n, //amt_nat 
  //                             0n) //ts_nat
  //   expect(r).toBe(0n);
  // });

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
              to : [bob.getPrincipal().toUint8Array()],
              amt : 100n,
          },
      },
    };
    let r = await can.add_record(my_action);
    expect(r).toBe(0n);
  });

  it("add_mint_burn1", async () => {
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
    console.log(r_mint);
    console.log("1");
    let r_burn = await can.add_record(my_burn_action);
    console.log(r_burn);
    console.log("2");
    expect(r_burn).toBe(0n);
  });

  async function passTime(n: number) {
    for (let i = 0; i < n; i++) {
      await pic.advanceTime(3 * 1000);
      await pic.tick(2);
    }
  }
});
