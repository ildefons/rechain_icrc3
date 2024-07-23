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
  DataCertificate,
  Account,
  GetBlocksArgs,
  TransactionRange,
  GetTransactionsResult,
  Value__1,
} from "./build/cert.idl.js";
import { HttpAgent, compare, lookup_path } from '@dfinity/agent';
import { verifyCertification } from '@dfinity/certificate-verification';

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

  it("test_mintblock_cert1", async () => {
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

    let data_cert: []|[DataCertificate] = await can.icrc3_get_tip_certificate();// : async ?Trechain.DataCertificate 
    if (data_cert != null) {
      let ddddd: undefined|DataCertificate = data_cert[0];
      if (typeof ddddd != "undefined") {

        const agent = new HttpAgent();
        await agent.fetchRootKey();
        // const tree = await verifyCertification({
        //   canisterId: Principal.fromText(canisterId),
        //   encodedCertificate: new Uint8Array(certificate).buffer,
        //   encodedTree: new Uint8Array(witness).buffer,
        //   rootKey: agent.rootKey,
        //   maxCertificateTimeOffsetMs: 50000,
        // });

        // const treeHash = lookup_path(['count'], tree);
        // if (!treeHash) {
        //   throw new Error('Count not found in tree');
        // }

        // const responseHash = await hashUInt32(count);
        // if (!(treeHash instanceof ArrayBuffer) || !equal(responseHash, treeHash)) {
        //   throw new Error('Count hash does not match');
        // }

        // countElement.innerText = String(count);



        console.log("cert: ", ddddd.certificate);
      };
    };
  });

  

  async function passTime(n: number) {
    for (let i = 0; i < n; i++) {
      await pic.advanceTime(3 * 1000);
      await pic.tick(2);
    }
  }
});
