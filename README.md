# Rechain

This Motoko library serves as a middleware framework enabling the integration of blockchain functionalities directly into dApps on the IC. It aims to abstract the complexities involved in blockchain operations, such as block creation, transaction management, hashing, certification and archival processes, allowing developers to incorporate ledger functionalities with minimal overhead.

**Core Components and Functionalities:**

Reducer Pattern for State Management: Employs a reducer pattern to manage state transitions based on actions. This approach allows for a more structured and predictable state management process, crucial for maintaining the consistency of blockchain states. It will allow easy replaying of state.

Has a modified stable memory version of the Sliding Window Buffer (by Research AG)

Modularity and Extensibility: Designed with modularity at its core, the library allows developers to define custom actions, errors, and reducer functions.

Reducer Libraries: Developers can publish their reducers as libraries, enabling others to incorporate these libraries into their canisters for efficient remote state synchronization. This process involves tracking a remote ledger's transaction log and reconstructing the required state segments in their canisters. This mechanism facilitates the development of dApps that can in certain cases can do remotely atomic synchronous operations within asynchronous environments, similar to the DeVeFi Ledger Middleware's capabilities.

**Example - ICRC3 compliant Ledger**

https://github.com/Neutrinomic/rechain_example

The provided example illustrates the use of the library to implement the ICRC3 ledger standard. It is based on the the ICDev/PanIndustrial implementation but with some variations ---->IMHERE:
For context, I am a full time Motoko developer working for Neutrinite foundation. Neutrinite has implemented a few key components that we would like to include in the ICRC3 implementation (AKA GitHub - PanIndustrial-Org/icrc3.mo: ICRC3 in motoko ):

A SlidingWindowBuffer to be used instead of a vector for the ledger (state.ledger). This helps by no having to create a new ledger everytime we create an archive canister
We have implemented a rechain/balancer in motoko that is basically is an event consumer where consumer can be customized with N different ways to process incoming transcations ( Motoko Rechain (Blockchain Middleware - ICRC-3 related) )
In the process of adapting the code with new components I my be breaking things and I need to test. This is the reason…

We are creating an abstract library - Rechain. Not a ledger. It will be used for apps that want to have icrc-3 logs with custom block schemas. And later used for following another canister icrc-3 log and reducing the current state from it.

**ICRC-3 problems**
- (not using) Generic Values are hard to use and probably prone to errors. Our reducers will have to reduce Generic Values if we want to replay state. Motoko CDK could add support for these that won't result in bloated code at some point in the future. These also need a schema. Sounds like what Candid is supposed to do  https://forum.dfinity.org/t/icrc-3-draft-v2-and-next-steps/25132/3
- (currently using) Hashing Candid binary format has other problems, but these can be fixed by making Candid produce the same binary on different platforms or ignored if we restrict hash verification only to Motoko canisters https://forum.dfinity.org/t/icrc-3-draft-v2-and-next-steps/25132/6 


## Install
```
nvm 21.4
go to test
yarn
built
```

## Usage/testing



# rechain_icrc3: rechain library and ICRC3 ledger demonstration

I think I am using a lot of the ICDev/PanIndustrial implementation but with some variations:
For context, I am a full time Motoko developer working for Neutrinite foundation. Neutrinite has implemented a few key components that we would like to include in the ICRC3 implementation (AKA GitHub - PanIndustrial-Org/icrc3.mo: ICRC3 in motoko ):

A SlidingWindowBuffer to be used instead of a vector for the ledger (state.ledger). This helps by no having to create a new ledger everytime we create an archive canister
We have implemented a rechain/balancer in motoko that is basically is an event consumer where consumer can be customized with N different ways to process incoming transcations ( Motoko Rechain (Blockchain Middleware - ICRC-3 related) )
In the process of adapting the code with new components I my be breaking things and I need to test. This is the reason…

We are creating an abstract library - Rechain. Not a ledger. It will be used for apps that want to have icrc-3 logs with custom block schemas. And later used for following another canister icrc-3 log and reducing the current state from it.

Under development

Based on ...

## Install
```
mops add icrc3-mo
```

## Usage
```motoko
import ICRC3 "mo:icrc3.mo";
```

## Initialization

This ICRC3 class uses a migration pattern as laid out in https://github.com/ZhenyaUsenko/motoko-migrations, but encapsulates the pattern in the Class+ pattern as described at https://forum.dfinity.org/t/writing-motoko-stable-libraries/21201 . As a result, when you insatiate the class you need to pass the stable memory state into the class:

```
stable var icrc3_migration_state = ICRC3.init(ICRC3.initialState() , #v0_1_0(#id), _args, init_msg.caller);

  let #v0_1_0(#data(icrc3_state_current)) = icrc3_migration_state;

  private var _icrc3 : ?ICRC3.ICRC3 = null;

  private func get_icrc3_environment() : ICRC3.Environment{
    ?{
      updated_certification = ?updated_certification;
      get_certificate_store = ?get_certificate_store;
    };
  };

  private func updated_certification(cert: Blob, lastIndex: Nat) : Bool{

    ct.setCertifiedData();
    return true;
  };

  func icrc3() : ICRC3.ICRC3 {
    switch(_icrc3){
      case(null){
        let initclass : ICRC3.ICRC3 = ICRC3.ICRC3(?icrc3_migration_state, Principal.fromActor(this), get_icrc3_environment());
        _icrc3 := ?initclass;
        initclass;
      };
      case(?val) val;
    };
  };

```
The above pattern will allow your class to call icrc3().XXXXX to easily access the stable state of your class and you will not have to worry about pre or post upgrade methods.

Init args:

```
  public type InitArgs = {
      maxActiveRecords : Nat; //allowed max active records on this canister
      settleToRecords : Nat; //number of records to settle to during the clean up process
      maxRecordsInArchiveInstance : Nat; //specify the max number of archive items to put on an archive instance
      maxArchivePages : Nat; //Max number of pages allowed on the archivserver
      archiveIndexType : SW.IndexType; //Index type to use for the memory of the archive
      maxRecordsToArchive : Nat; //Max number of archive items to archive in one round
      archiveCycles : Nat; //number of cycles to sent to a new archive canister;
      archiveControllers : ??[Principal]; //override the default controllers. The canister will always add itself to this group;
    };
```

For information on maxArchivePages and stable memory management, see https://github.com/skilesare/StableWriteOnly.mo. This configuration allows your archives to use up to 96GB(as of 12/5/2023) stable memory.

## Maintenance and Archival

Each time a transaction is added, the ledger checks to see if it has exceeded its max length. If it has, it sets a timer to run in the next round to run the archive.  It will only attempt to archive a chunk at a time as configured and will set it self to run again if it was unable to reach its settled records.

When the first archive reaches its limit, the class will create a new archive canister and send it the number of configured cycles. It will fail silently if there are not enough cycles.

## Transaction Log Best Practices

This class supports an ICRC3 style, write only transaction log. It supports archiving to other canisters on the same subnet.  Multi subnet archiving and archive splitting is not yet supported, but is planned for future versions.

Typically you want to keep a small number of transactions on your main canister with frequent and often archival of transactions to the archive. For example, the ICP ledger uses 2000 transactions as the max and 1000 as the settle to. If you utilize stable memory, you should be able to write a very large number of transactions to your archive.  We do not yet have benchmarks and have yet to do max out testing, but we feel comfortable saying that 4GB or 62500 pages should be safe.  You will need to determine for your self what the max number of records that can fit into the alloted pages is.  If you have a variable or unbounded transaction type you may need to consider putting your max pages higher and number of transactions lower.

Future versions may make this more dynamic.

Future Todos:

- Archive Upgrades
- Multi-subnet archives
- Archive Splitting
- Automatic memory monitoring