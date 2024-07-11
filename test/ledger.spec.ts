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
  Value__1,
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

  it("retrieve_blocks_online1", async () => {
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

  it("check_online_block_content1", async () => {
    //let tr: TransactionRange =  {start:10n,length:3n};
    let my_block_args: GetBlocksArgs = [
      {start:0n,length:1n},
      //{start:20n,length:3n},
    ]

    let my_blocks:GetTransactionsResult = await can.icrc3_get_blocks(my_block_args);
    // console.log(my_blocks.blocks[0].id);
    // console.log(my_blocks.blocks[0].block);  // how to deserialize?
    //let my_block = my_blocks[0].block;//: []|[Value__1]
    
    // let aux = await can.testme();
    // console.log(aux);
    // // if(aux.hasOwnProperty('A')) {
    // //   console.log(aux[0]);
    // // };
    // if ('A' in aux) {
    //   console.log(aux.A);
    // };

    // console.log(my_blocks.blocks[0]);
    let my_block_id = -1n;
    let my_block_ts = -1n;
    let my_created_at_time = -1n;
    let my_memo;//: Uint8Array | number[];
    let my_caller;//: Uint8Array | number[];
    let my_fee = -1n;
    let my_btype = '???';
    let my_payload_amt = -1n;//', { Map: [Array] } ]
    let my_payload_to;
    let my_payload_from;

    if (my_blocks.blocks[0].block[0] !== undefined) {
      
      const aux: Value__1 = my_blocks.blocks[0].block[0];
      if ('id' in my_blocks.blocks[0]) {
        my_block_id = my_blocks.blocks[0].id;
        // console.log("id:",my_block_id);
      }
      if ('Map' in aux) {
        const aux2 = aux.Map;
        // console.log("aux")
        // console.log(aux);
        // console.log("aux2 = aux.Map")
        // console.log(aux2);
        // console.log(aux2[0][1]);
        if ('Map' in aux2[0][1]) {
          const aux3 = aux2[0][1];
          // console.log(aux3.Map);
          // console.log(aux3.Map[0]);
          // console.log(aux3.Map[0][0]);
          // console.log(aux3.Map[0][1]);
          if ('Nat' in aux3.Map[0][1]) {
            // console.log(aux3.Map[0][1].Nat);
            my_block_ts = aux3.Map[0][1].Nat;
          }
          if ('Nat' in aux3.Map[1][1]) {
            // console.log(aux3.Map[1][1].Nat);
            my_created_at_time = aux3.Map[1][1].Nat;
          }
          if ('Blob' in aux3.Map[2][1]) {
            // console.log(aux3.Map[2][1].Blob);
            my_memo = aux3.Map[2][1].Blob;
          }
          if ('Blob' in aux3.Map[3][1]) {
            // console.log(aux3.Map[3][1].Blob);
            my_caller = aux3.Map[3][1].Blob;
          }
          if ('Nat' in aux3.Map[4][1]) {
            // console.log(aux3.Map[4][1].Nat);
            my_fee = aux3.Map[4][1].Nat;
          } 
          if ('Text' in aux3.Map[5][1]) {
            // console.log(aux3.Map[5][1].Text);
            my_btype = aux3.Map[5][1].Text;
          } 
          if ('Map' in aux3.Map[6][1]) {
            // console.log(aux3.Map[6][1].Map);
            const aux4 = aux3.Map[6][1];
            if ('Nat' in aux4.Map[0][1]) {
              // console.log(aux4.Map[0][1].Nat);
              my_payload_amt = aux4.Map[0][1].Nat;
            }
            if ('Array' in aux4.Map[1][1]) {
              // console.log(aux4.Map[1][1].Array);
              // console.log(aux4.Map[1][0]);
              if (aux4.Map[1][0] == 'to'){
                const aux5 = aux4.Map[1][1].Array;
                // console.log(aux5);
                if ('Blob' in aux5[0]) {
                  // console.log(aux5[0].Blob);
                  my_payload_to = aux5[0].Blob
                }
              } else if (aux4.Map[1][0] == 'from'){
                const aux5 = aux4.Map[1][1].Array;
                // console.log(aux5);
                if ('Blob' in aux5[0]) {
                  // console.log(aux5[0].Blob);
                  my_payload_from = aux5[0].Blob
                }
              }
            }
            if (typeof aux4.Map[2] != "undefined") {

              if ('Array' in aux4.Map[2][1]) {
                // console.log(aux4.Map[2][1].Array);
                // console.log(aux4.Map[2][0]);
                if (aux4.Map[2][0] == 'to'){
                  const aux5 = aux4.Map[2][1].Array;
                  // console.log(aux5);
                  if ('Blob' in aux5[0]) {
                    // console.log(aux5[0].Blob);
                    my_payload_to = aux5[0].Blob
                  }
                } else if (aux4.Map[2][0] == 'from'){
                  const aux5 = aux4.Map[2][1].Array;
                  // console.log(aux5);
                  if ('Blob' in aux5[0]) {
                    // console.log(aux5[0].Blob);
                    my_payload_from = aux5[0].Blob
                  }
                }
              }
            }
          } 
          //<---IMHERE continue decode function
          console.log("id:",my_block_id);
          console.log("ts",my_block_ts);
          console.log("my_created_at_time:",my_created_at_time);
          console.log("memo:",my_memo);
          console.log("caller:",my_caller);
          console.log("fee:",my_fee);
          console.log("btype:",my_btype);
          console.log("amt:",my_payload_amt);
          console.log("to:",my_payload_to);
          console.log("from:",my_payload_from);
        }
      }
      
      //console.log(aux);
    };
    
    //   if ('Map' in my_block[0]) {
    //   console.log(aux.A);
    // };
    // if(my_block[0].hasOwnProperty('Map'))
    // {
    //   console.log("ddd");//my_block[0]);
    // }
    expect(my_blocks.blocks.length).toBe(1);
  });

  // check bugs in get_blocks (-1)
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
