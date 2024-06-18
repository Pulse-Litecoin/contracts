// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'hardhat/console.sol';

//        ____ _____ ____ __  __ _                  _     _
//  _ __ | __ )_   _/ ___|  \/  (_)_ __   ___  __ _| |__ | | ___
// | '_ \|  _ \ | || |   | |\/| | | '_ \ / _ \/ _` | '_ \| |/ _ \
// | |_) | |_) || || |___| |  | | | | | |  __/ (_| | |_) | |  __/
// | .__/|____/ |_| \____|_|  |_|_|_| |_|\___|\__,_|_.__/|_|\___|
// |_|
//

abstract contract Asic {
  event Transfer(address indexed from, address indexed to, uint value);

  function approve(address spender, uint amount) public virtual returns (bool);
  function balanceOf(address account) public view virtual returns (uint);
  function transfer(address to, uint amount) public virtual returns (bool);
  function transferFrom(address sender, address recipient, uint amount) public virtual returns(bool);
}

abstract contract PulseBitcoin {
  uint public miningRate;
  uint public miningFee;
  uint public totalpSatoshisMined;
  uint public previousHalvingThresold;
  uint public currentHalvingThreshold;
  uint public numOfHalvings;
  uint public atmMultiplier;

  struct MinerStore {
    uint128 bitoshisMiner;
    uint128 bitoshisReturned;
    uint96 pSatoshisMined;
    uint96 bitoshisBurned;
    uint40 minerId;
    uint24 day;
  }

  mapping(address => MinerStore[]) public minerList;

  event Transfer(address indexed from, address indexed to, uint value);

  // Error hashes
  // ATMEventIsOver: 0xd9183b01
  // InvalidToken: 0xc1ab6dc1
  // ATMPointsToSmall: 0x6faf0395
  // NotOwnerOfATM: 0x32181adb
  // ATMNotActive: 0xa9dbd6bd
  // AsicMinerToLarge: 0x7df92805
  // CannotEndATMWithinEventPeriod: 0x6077e059
  // InsufficientBalance: 0xcf479181
  // InvalidAmount: 0x7c83fcf0
  // InvalidMinerId: 0x1fe74735
  // MinerListEmpty: 0x9d941f79
  // InvalidMinerIndex: 0xff32bb25
  // CannotEndMinerEarly: 0xde50ebd9

  function minerCount(address minerAddress) public virtual view returns (uint);
  function minerStart(uint bitoshisMiner) public virtual;
  function minerEnd(uint minerIndex, uint minerId, address minerAddr) public virtual;
  function currentDay() public virtual view returns (uint);

  // Standard ERC-20 functions
  function approve(address spender, uint amount) public virtual returns (bool);
  function balanceOf(address account) public view virtual returns (uint);
  function transfer(address to, uint amount) public virtual returns (bool);
  function transferFrom(address sender, address recipient, uint amount) public virtual returns(bool);
}

abstract contract PulseBitcoinMineable {
  PulseBitcoin public immutable pBTC;
  Asic public immutable ASIC;

  struct MinerStore {
    uint128 bitoshisMiner;
    uint128 bitoshisReturned;
    uint96 pSatoshisMined;
    uint96 bitoshisBurned;
    uint40 minerId;
    uint24 day;
  }

  struct MinerCache {
    uint bitoshisMiner;
    uint bitoshisReturned;
    uint pSatoshisMined;
    uint bitoshisBurned;
    uint minerId;
    uint day;
  }

  mapping(address => MinerStore[]) public minerList;

  error UnknownMiner(MinerStore[] minerList, MinerCache miner);
  error InvalidMinerId(uint minerId);
  error InvalidMinerIndex(uint minerIndex);
  error CannotEndMinerEarly(uint256 servedDays, uint256 requiredDays);

  constructor() {
    pBTC = PulseBitcoin(address(0x5EE84583f67D5EcEa5420dBb42b462896E7f8D06));
    ASIC = Asic(address(0x347a96a5BD06D2E15199b032F46fB724d6c73047));

    // Approve the pBTC contract to spend our ASIC so we can mine.
    ASIC.approve(address(pBTC), type(uint).max);
  }

  function _minerStart(
    uint bitoshis
  ) internal returns (
    MinerCache memory
  ) {

    pBTC.minerStart(bitoshis);

    MinerCache memory miner = _minerAt(_lastMinerIndex());
    _minerAdd(minerList[msg.sender], miner);

    return miner;

  }

  function _minerEnd(
    int minerIndex,
    uint minerOwnerIndex,
    uint minerId,
    address minerOwner
  ) internal returns (
    MinerCache memory
  ) {
    
    MinerCache memory miner = _minerLoad(minerOwnerIndex, minerOwner);

    // Do we have the correct miner?
    if(miner.minerId != minerId) {
      revert InvalidMinerId(minerId);
    }

    if(minerIndex < 0) {
      // Try to find the miner index
      minerIndex = _minerIndexSearch(miner);
    }

    // The miner index still wasn't found. Must've been ended already
    if(minerIndex < 0) {

      // Make sure the miner is old enough. 
      // pBTC.minerEnd does this for us below.
      uint256 servedDays = _currentDay() - miner.day;
      if (servedDays < _miningDuration()) {
        revert CannotEndMinerEarly(servedDays, _miningDuration());
      }

    } else {

      // End the miner as per usual
      pBTC.minerEnd(uint(minerIndex), minerId, address(this));

    }

    _minerRemove(minerList[minerOwner], miner);

    return miner;

  }

  function _minerAt(uint index) internal view returns (MinerCache memory) {
    (
      uint128 bitoshisMiner,
      uint128 bitoshisReturned,
      uint96 pSatoshisMined,
      uint96 bitoshisBurned,
      uint40 minerId,
      uint24 day
    ) = pBTC.minerList(address(this), index);

    return MinerCache({
      minerId: minerId,
      bitoshisMiner: bitoshisMiner,
      pSatoshisMined: pSatoshisMined,
      bitoshisBurned: bitoshisBurned,
      bitoshisReturned: bitoshisReturned,
      day: day
    });
  }

  function _minerLoad(
    uint minerIndex,
    address minerOwner
  ) internal view returns (
    MinerCache memory miner
  ) {
    MinerStore storage _miner = minerList[minerOwner][minerIndex];

    return MinerCache({
      minerId: _miner.minerId,
      bitoshisMiner: _miner.bitoshisMiner,
      pSatoshisMined: _miner.pSatoshisMined,
      bitoshisBurned: _miner.bitoshisBurned,
      bitoshisReturned: _miner.bitoshisReturned,
      day: _miner.day
    });
  }

  function _minerAdd(
    MinerStore[] storage minerListRef,
    MinerCache memory miner
  ) internal {
    minerListRef.push(MinerStore(
      uint128(miner.bitoshisMiner),
      uint128(miner.bitoshisReturned),
      uint96(miner.pSatoshisMined),
      uint96(miner.bitoshisBurned),
      uint40(miner.minerId),
      uint24(miner.day)
    ));
  }

  function _minerRemove(
    MinerStore[] storage minerListRef,
    MinerCache memory miner
  ) internal {
    uint minerListLength = minerListRef.length;

    for(uint i=0; i < minerListLength;) {
      if(minerListRef[i].minerId == miner.minerId) {

        uint lastIndex = minerListLength - 1;

        if(i != lastIndex) {
          minerListRef[i] = minerListRef[lastIndex];
        }

        minerListRef.pop();

        break;

      }

      unchecked {
        i++;
      }
    }

    // Did it remove anything?
    if(minerListRef.length == minerListLength) {
      revert UnknownMiner(minerListRef, miner);
    }
  }

  // @dev Find the minerIndex of a miner. 
  // This is heavy, only runs if we don't know the index
  function _minerIndexSearch(
    MinerCache memory miner
  ) internal view returns (int) {
    uint minerListLength = pBTC.minerCount(address(this));
    int foundMinerIndex = -1;

    for(uint i=0; i < minerListLength;) {
      console.log("Had to loop", i);

      if(_minerAt(i).minerId == miner.minerId) {
        foundMinerIndex = int(i);

        break;
      }

      unchecked {
        i++;
      }
    }

    return foundMinerIndex;
  }

  function _miningDuration() internal pure returns (uint) {
    return 30;
  }

  function _withdrawGracePeriod() internal pure returns (uint) {
    return 30;
  }

  function _daysForPenalty() internal pure returns (uint) {
    return _miningDuration() + _withdrawGracePeriod();
  }

  function _lastMinerIndex() internal view returns (uint) {
    return pBTC.minerCount(address(this)) - 1;
  }

  function _currentDay() internal view returns (uint) {
    return pBTC.currentDay();
  }
}
