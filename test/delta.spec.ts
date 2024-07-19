import { Principal } from '@dfinity/principal';
import { resolve } from 'node:path';
import { Actor, PocketIc, createIdentity } from '@hadronous/pic';
import { IDL } from '@dfinity/candid';
import { _SERVICE as TestService, idlFactory as TestIdlFactory, init, ArchivedTransactionResponse, GetBlocksResult } from './build/delta.idl.js';

// ILDE import {ICRCLedgerService, ICRCLedger} from "./icrc_ledger/ledgerCanister";
//@ts-ignore
import {toState} from "@infu/icblast";
// Jest can't handle multi threaded BigInts o.O That's why we use toState

const WASM_PATH = resolve(__dirname, "./build/delta.wasm");

export async function TestCan(pic:PocketIc) {
    
    const fixture = await pic.setupCanister<TestService>({
        idlFactory: TestIdlFactory,
        wasm: WASM_PATH,
        arg: IDL.encode(init({ IDL }), []),
    });

    await pic.addCycles(fixture.canisterId, 200_000_000_000_000);
    
    return fixture;
};


describe('Delta', () => {
    let pic: PocketIc;
    let can: Actor<TestService>;
    let canCanisterId: Principal;

    // const jo = createIdentity('superSecretAlicePassword');
    // const bob = createIdentity('superSecretBobPassword');
  
    beforeAll(async () => {
      pic = await PocketIc.create(process.env.PIC_URL); 
      const fixture = await TestCan(pic);
      can = fixture.actor;
      canCanisterId = fixture.canisterId; 

      await can.set_ledger_canister();
    });
  
    afterAll(async () => {
      await pic.tearDown();  //ILDE: this means "it removes the replica"
    });

    it('empty dispatch', async () => {
      let r = await can.dispatch([]);
      expect(r.length).toBe(0);
    });

    it('empty log', async () => {
        let rez = await can.icrc3_get_blocks([{
            start: 0n,
            length: 100n
        }]);
        expect(rez.archived_blocks.length).toBe(0);
        expect(rez.blocks.length).toBe(0);
        expect(rez.log_length).toBe(0n);
    });

    it("dispatch 1 action", async () => {

      let r = await can.dispatch([{
        ts:12340n,
        created_at_time: 1721045569580000n,
        memo: [0,1,2,3,4],
        caller: Principal.fromText("eqsml-lyaaa-aaaaq-aacdq-cai"),
        fee: 1000n,
        payload: {
          swap : {amt: 123456n}
        }
      }]);
      expect(toState(r[0]).Ok).toBe("1");
    });

    it('icrc3_get_blocks with 1 block', async () => {
      let rez = await can.icrc3_get_blocks([{
          start: 0n,
          length: 100n
      }]);
      let strblock = JSON.stringify(toState(rez.blocks[0]));
      expect(strblock).toBe('{"id":"0","block":[{"Map":[["tx",{"Map":[["ts",{"Nat":"12340"}],["created_at_time",{"Nat":"1721045569580000"}],["memo",{"Blob":"0001020304"}],["caller",{"Blob":"00000000020000870101"}],["fee",{"Nat":"1000"}],["btype",{"Text":"1swap"}],["payload",{"Map":[["amt",{"Nat":"123456"}]]}]]}]]}]}');
      expect(rez.log_length).toBe(1n);
      expect(rez.archived_blocks.length).toBe(0);
      expect(rez.blocks.length).toBe(1);
      
    });


    it("dispatch 300 actions in 300 calls", async () => {
      for (let i=0; i<300; i++) {
        let r = await can.dispatch([{
          ts:12340n,
          created_at_time: 1721045569580000n,
          memo: [0,1,2,3,4],
          caller: Principal.fromText("eqsml-lyaaa-aaaaq-aacdq-cai"),
          fee: 1000n,
          payload: {
            swap : {amt: 123456n}
          }
        }]);
        expect(toState(r[0]).Ok).toBe((2 + i).toString());
      }
     await passTime(20);
    });


    it('icrc3_get_blocks 100', async () => {
      let rez = await can.icrc3_get_blocks([{
          start: 0n,
          length: 100n
      }]);
      let archive_rez = await getArchived(rez.archived_blocks[0]);
      
      expect(archive_rez.blocks[5].id).toBe(5n);
      
    });


      it('icrc3_get_blocks first 301', async () => {
      let rez = await can.icrc3_get_blocks([{
          start: 0n,
          length: 500n
      }]);

      
      expect(rez.blocks[0].id).toBe(240n);
      expect(rez.blocks[ rez.blocks.length - 1].id).toBe(300n);

      let archive_rez_0 = await getArchived(rez.archived_blocks[0]);
      expect(archive_rez_0.blocks[0].id).toBe(0n);
      expect(archive_rez_0.blocks[ archive_rez_0.blocks.length - 1].id).toBe(119n);

      let archive_rez_1 = await getArchived(rez.archived_blocks[1]);
      expect(archive_rez_1.blocks[0].id).toBe(120n);
      expect(archive_rez_1.blocks[ archive_rez_1.blocks.length - 1].id).toBe(239n);

    });



    it("dispatch 300 actions in 1 call", async () => {
        let r = await can.dispatch(Array.from({ length: 300 }, () => ({
          ts:12340n,
          created_at_time: 1721045569580000n,
          memo: [0,1,2,3,4],
          caller: Principal.fromText("eqsml-lyaaa-aaaaq-aacdq-cai"),
          fee: 1000n,
          payload: {
            swap : {amt: 123456n}
          }
        })));
        expect(toState(r[0]).Ok).toBe("302");
        await passTime(20);
    });


    it('icrc3_get_blocks 601', async () => {
      let rez = await can.icrc3_get_blocks([{
          start: 0n,
          length: 800n
      }]);

      expect(rez.blocks[0].id).toBe(571n);
      expect(rez.blocks[ rez.blocks.length - 1].id).toBe(600n);

      let archive_rez_0 = await getArchived(rez.archived_blocks[0]);
      expect(archive_rez_0.blocks[0].id).toBe(0n);
      expect(archive_rez_0.blocks[ archive_rez_0.blocks.length - 1].id).toBe(119n);

      let archive_rez_1 = await getArchived(rez.archived_blocks[1]);
      expect(archive_rez_1.blocks[0].id).toBe(120n);
      expect(archive_rez_1.blocks[ archive_rez_1.blocks.length - 1].id).toBe(239n);

      let archive_rez_2 = await getArchived(rez.archived_blocks[2]);
      expect(archive_rez_2.blocks[0].id).toBe(240n);
      expect(archive_rez_2.blocks[ archive_rez_2.blocks.length - 1].id).toBe(359n);

      let archive_rez_3 = await getArchived(rez.archived_blocks[3]);
      expect(archive_rez_3.blocks[0].id).toBe(360n);
      expect(archive_rez_3.blocks[ archive_rez_3.blocks.length - 1].id).toBe(479n);

      let archive_rez_4 = await getArchived(rez.archived_blocks[4]);
      expect(archive_rez_4.blocks[0].id).toBe(480n);
      expect(archive_rez_4.blocks[ archive_rez_4.blocks.length - 1].id).toBe(570n);

    });


    it('upgrade canister', async () => {
      let can_last_updated = await can.last_modified();
      await pic.upgradeCanister({ canisterId: canCanisterId, wasm: WASM_PATH });
      let can_last_updated_after = await can.last_modified();
      expect(Number(can_last_updated)).toBeLessThan(Number(can_last_updated_after));
    });




    // it('icrc3_get_blocks request 1000 blocks', async () => {
    //   let rez = await can.icrc3_get_blocks([{
    //       start: 0n,
    //       length: 1000n
    //   }]);
   
    //   expect(rez.log_length).toBe(601n);
  
    // });

    // it('icrc3_get_blocks 3 requested ranged', async () => {
    //   let rez = await can.icrc3_get_blocks([{
    //       start: 0n,
    //       length: 150n
    //     }, {
    //       start: 50n,
    //       length: 300n
    //     }, {
    //       start: 550n,
    //       length: 630n
    //   }]);
   
    //   let jstr = JSON.stringify(toState(rez.archived_blocks));

    //   expect(jstr).toBe('[{"args":[{"start":"0","length":"120"},{"start":"50","length":"70"}],"callback":["lqy7q-dh777-77777-aaaaq-cai","icrc3_get_blocks"]},{"args":[{"start":"120","length":"30"},{"start":"120","length":"120"}],"callback":["lz3um-vp777-77777-aaaba-cai","icrc3_get_blocks"]},{"args":[{"start":"240","length":"110"}],"callback":["l62sy-yx777-77777-aaabq-cai","icrc3_get_blocks"]},{"args":[{"start":"550","length":"21"}],"callback":["lm4fb-uh777-77777-aaacq-cai","icrc3_get_blocks"]}]')
  
    // });

    async function passTime(n:number) {
      for (let i=0; i<n; i++) {
          await pic.advanceTime(3*1000);
          await pic.tick(2);
        }
    }

    async function getArchived(arch_param:ArchivedTransactionResponse) : Promise<GetBlocksResult> {
      let archive_principal = Principal.fromText(toState(arch_param).callback[0]);
      const archive_actor = pic.createActor<TestService>(TestIdlFactory, archive_principal);
      let args = arch_param.args[0]
      return await archive_actor.icrc3_get_blocks([args]);
    }
});