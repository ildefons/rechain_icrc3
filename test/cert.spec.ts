import { Principal } from "@dfinity/principal";
import { resolve } from "node:path";
import { Actor, PocketIc, createIdentity} from "@hadronous/pic";

import { IDL } from "@dfinity/candid";
import {
  _SERVICE as TestService,
  idlFactory as TestIdlFactory,
  init,
} from "./build/cert.idl.js";

import {
  Action,
  Account,
  GetBlocksArgs,
  TransactionRange,
  GetTransactionsResult,
  Value__1,
} from "./build/cert.idl.js";


// ILDE import {ICRCLedgerService, ICRCLedger} from "./icrc_ledger/ledgerCanister";
//@ts-ignore
import { toState } from "@infu/icblast";
// Jest can't handle multi threaded BigInts o.O That's why we use toState

const WASM_PATH = resolve(__dirname, "./build/cert.wasm");
export async function TestCan(pic:PocketIc) {
    
  const fixture = await pic.setupCanister<TestService>({
      idlFactory: TestIdlFactory,
      wasm: WASM_PATH,
      arg: IDL.encode(init({ IDL }), []),
  });

  return fixture;
};

describe("Cert", () => {
  let pic: PocketIc;
  let can: Actor<TestService>;
  let canCanisterId: Principal;

  const jo = createIdentity('superSecretAlicePassword');
  
  beforeAll(async () => {
    pic = await PocketIc.create(process.env.PIC_URL); 
    const fixture = await TestCan(pic);
    can = fixture.actor;
    canCanisterId = fixture.canisterId; 

    // await can.set_ledger_canister();

    //await can.set_ledger_canister();
  });

  afterAll(async () => {
    await pic.tearDown(); //ILDE: this means "it removes the replica"
  });

  it("test1check_burnblock_to", async () => {
    let my_mint_action: Action = {
      ts : 0n,
      created_at_time : [0n], //?Nat64
      memo: [], //?Blob;
      caller: jo.getPrincipal(),  
      fee: [], //?Nat
      payload : {
          mint : {
              amt : 50n,
              to : [jo.getPrincipal().toUint8Array()],
          },
      },
    };
    let r_mint = await can.add_record(my_mint_action);
    expect(true).toBe('Ok' in r_mint);
  });

  

  async function passTime(n: number) {
    for (let i = 0; i < n; i++) {
      await pic.advanceTime(3 * 1000);
      await pic.tick(2);
    }
  }
});
