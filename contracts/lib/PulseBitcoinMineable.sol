// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

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
  uint public previousHalvingThresold;
  uint public currentHalvingThreshold;
  uint public totalpSatoshisMined;
  uint public numOfHalvings;

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
  PulseBitcoin public immutable PLSB;
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
  error PLSBMinerAlreadyEnded(uint minerId);

  constructor() {
    PLSB = PulseBitcoin(address(0x5EE84583f67D5EcEa5420dBb42b462896E7f8D06));
    ASIC = Asic(address(0x347a96a5BD06D2E15199b032F46fB724d6c73047));

    // Approve the PLSB contract to spend our ASIC so we can mine.
    ASIC.approve(address(PLSB), type(uint).max);
  }

  function _minerStart(
    uint bitoshis
  ) internal returns (
    MinerCache memory
  ) {

    PLSB.minerStart(bitoshis);

    MinerCache memory miner = _minerAt(_lastMinerIndex());
    _minerAdd(minerList[msg.sender], miner);

    return miner;

  }

  function _minerEnd(
    uint minerIndex,
    uint minerOwnerIndex,
    uint minerId,
    address minerOwner
  ) internal returns (
    MinerCache memory
  ) {
    
    MinerCache memory miner = _minerLoad(minerOwnerIndex, minerOwner);

    // Check for this miner
    if(miner.minerId != minerId) {
      revert InvalidMinerId(minerId);
    }

    // Check PLSB for this miner
    try PLSB.minerList(address(this), minerIndex) {
      
      // A miner at this index was found. Is it this one?
      MinerCache memory _miner = _minerAt(minerIndex);

      if(uint(_miner.minerId) == minerId) {

        // Yep, end it
        PLSB.minerEnd(minerIndex, minerId, address(this));

      } else {

        // Try recovery
        _recoverAndEndMiner(minerIndex, minerId);

      }

    } catch {

      // The miner at the index didn't exist. Run recovery
      _recoverAndEndMiner(minerIndex, minerId);
      
    }

    _minerRemove(minerList[minerOwner], miner);

    return miner;

  }

  function _recoverAndEndMiner(
    uint minerIndex, 
    uint minerId
  ) internal {
    // At this point, does it really matter if it's validated? We have the minerOwner and it's index.
    // That's all we care about. 

    // Reconcile the minerIndex && minerId by looping through all the miners
    uint minerLength = PLSB.minerCount(address(this));
    uint minerCount = minerLength == 0 ? 0 : minerLength - 1;
    
    uint _minerId; 
    uint _minerIndex;

    for (uint i = 0; i <= minerCount;) {
      if(i != minerIndex) {

        (,,,,uint __minerId,) = PLSB.minerList(address(this), i);

        if(uint(__minerId) == minerId) {
          _minerIndex = i;
          _minerId = __minerId;
          break;
        }

      }

      unchecked {
        i++;
      }
    }

    if(_minerId != 0) {

      // If we have a _minerId that isn't zero, there is a real miner that exists with this id.
      // This is a case of a mismatched minerIndex. We can safely end it.        
      PLSB.minerEnd(_minerIndex, _minerId, address(this));

    }
  }

  function _minerAt(uint index) internal view returns (MinerCache memory) {
    (
      uint128 bitoshisMiner,
      uint128 bitoshisReturned,
      uint96 pSatoshisMined,
      uint96 bitoshisBurned,
      uint40 minerId,
      uint24 day
    ) = PLSB.minerList(address(this), index);

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
    return PLSB.minerCount(address(this)) - 1;
  }

  function _currentDay() internal view returns (uint) {
    return PLSB.currentDay();
  }
}
