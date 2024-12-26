// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

error TokenNotExists(uint256 tokenId);
error NotExists();
error ArrayEmpty();
error ArrayOverflow();
error NotAllowed();
error InsufficientBalance();
error Exists();
error InvalidValue(uint256 value);
error PriceEmpty();

// Enum Token Rarity
enum RarityTypes {
    Empty, // 0
    Common, // 1
    Uncommon, // 2
    Rare, // 3
    Epic, // 4
    Legendary, // 5
    Ancient // 6
}

// Enum NFT Types
enum NftTypes {
    None, // 0
    Fish, // 1
    Boat // 2
}

// Enum Token Types
enum TokenTypes {
    None, // 0
    Governance, // 1
    Utility // 2
}

// Enum Creature Types for Fish
enum CreatureTypes {
    None, // 0
    Loyal, // 1
    Fish // 2
}

// Enum Engine Types for Boat
enum EngineTypes {
    None, // 0
    Generic, // 1
    Ufo, // 2
    Solar // 3
}

/* FishFactory  */
//------------------
struct FishMetaData {
    uint8 Rarity;
    uint8 CreatureType;
    uint16 Production;
    uint32 Id;
}

/* BoatFactory  */
//------------------
struct BoatMetaData {
    uint8 Rarity;
    uint8 EngineType;
    uint8 Capacity; // max fish count
    uint8 FuelTank; // max fuel capacity
    uint16 WaitTime; // wait time in hours. range : 1 ~ 65000
    uint32 Id;
}

/* Global for non-fungible tokens  */
//------------------
struct Amounts {
    uint32 Id;
    uint64 Balance;
}

/* ContractFactory  */
//------------------
struct AppConfig {
    // one block completion time in seconds. default : 5
    uint8 BlockPeriod;
    // daily total blocks. default : 17280
    uint32 DailyBlock;
}
