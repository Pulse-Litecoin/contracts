// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

//        ____ _____ ____ __  __ _                  _     _
//  _ __ | __ )_   _/ ___|  \/  (_)_ __   ___  __ _| |__ | | ___
// | '_ \|  _ \ | || |   | |\/| | | '_ \ / _ \/ _` | '_ \| |/ _ \
// | |_) | |_) || || |___| |  | | | | | |  __/ (_| | |_) | |  __/
// | .__/|____/ |_| \____|_|  |_|_|_| |_|\___|\__,_|_.__/|_|\___|
// |_|
//
// This contract allows any contract that inherits it to mine PulseBitcoin.
// Supports recovering miners that are ended on the PulseBitcoin contract directly.

abstract contract Asic {
  event Transfer(address indexed from, address indexed to, uint256 value);

  function approve(address spender, uint256 amount) public virtual returns (bool);
  function balanceOf(address account) public view virtual returns (uint256);
  function transfer(address to, uint256 amount) public virtual returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) public virtual returns(bool);
}

abstract contract PulseBitcoin {
  uint256 public miningRate;
  uint256 public miningFee;
  uint256 public totalpSatoshisMined;
  uint256 public previousHalvingThresold;
  uint256 public currentHalvingThreshold;
  uint256 public numOfHalvings;
  uint256 public atmMultiplier;

  struct MinerStore {
    uint128 bitoshisMiner;
    uint128 bitoshisReturned;
    uint96 pSatoshisMined;
    uint96 bitoshisBurned;
    uint40 minerId;
    uint24 day;
  }

  mapping(address => MinerStore[]) public minerList;

  event Transfer(address indexed from, address indexed to, uint256 value);

  function minerCount(address minerAddress) public virtual view returns (uint256);
  function minerStart(uint256 bitoshisMiner) public virtual;
  function minerEnd(uint256 minerIndex, uint256 minerId, address minerAddr) public virtual;
  function currentDay() public virtual view returns (uint256);

  function approve(address spender, uint256 amount) public virtual returns (bool);
  function balanceOf(address account) public view virtual returns (uint256);
  function transfer(address to, uint256 amount) public virtual returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) public virtual returns(bool);
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
    uint256 bitoshisMiner;
    uint256 bitoshisReturned;
    uint256 pSatoshisMined;
    uint256 bitoshisBurned;
    uint256 minerId;
    uint256 day;
  }

  mapping(address => MinerStore[]) public minerList;

  error UnknownMiner(MinerStore[] minerList, MinerCache miner);
  error InvalidMinerId(uint256 minerId);
  error InvalidMinerIndex(uint256 minerIndex);
  error CannotEndMinerEarly(uint256 servedDays, uint256 requiredDays);

  constructor() {
    pBTC = PulseBitcoin(address(0x5EE84583f67D5EcEa5420dBb42b462896E7f8D06));
    ASIC = Asic(address(0x347a96a5BD06D2E15199b032F46fB724d6c73047));

    // Approve the pBTC contract to spend our ASIC so this contract can mine.
    ASIC.approve(address(pBTC), type(uint256).max);
  }

  // @remark -1 Is magic. It makes your function call less efficient!
  //  a minerIndex of -1 triggers the _minerEnd function to run _minerIndexSearch to find the minerIndex
  //  (which could loop quite a lot!)
  //  If you can call this function with the minerIndex, do that. 
  //  Otherwise, pass -1 & it'll do it. Just cost more. 
  //  Could potentially run into out of gas errors.

  // @notice Start the PLSB Miner.
  // @dev We store this miner as {msg.sender -> MinerCache instance}
  //   On the PLSB contract, our miners are stored as {pLTCContract -> MinerCache instance}
  //   We're duping this as {msg.sender -> MinerCache instance} so we can look it up later.
  //   See @remark -1 for details.
  function _minerStart(
    uint256 bitoshis
  ) internal returns (
    MinerCache memory
  ) {

    pBTC.minerStart(bitoshis);

    MinerCache memory miner = _minerAt(_lastMinerIndex());
    _minerAdd(minerList[msg.sender], miner);

    return miner;

  }

  // @notice End the PLSB miner
  // @param minerIndex The index of the pLTC contract miner's address on the PLSB contract
  //  This would be the miner's specific index on pLTC address. If you DON'T KNOW, specify -1. See @remark on -1
  // @param minerOwnerIndex The index of the miner's address using the pBTCMineable's address.
  //  This is the miner's ACTUAL miner. Like "who's mining"? The index above is just for saving unnessecary gas. 
  // @param minerId collected from the PLSB contract
  // @param minerOwner The owner of the miner
  // @return miner a instance of MinerCache
  function _minerEnd(
    int minerIndex,
    uint256 minerOwnerIndex,
    uint256 minerId,
    address minerOwner
  ) internal returns (
    MinerCache memory
  ) {
    
    MinerCache memory miner = _minerLoad(minerOwnerIndex, minerOwner);

    // Do we have the correct miner?
    if(miner.minerId != minerId) {
      revert InvalidMinerId(minerId);
    }

    // Try to find the miner index (This is what -1 triggers)
    if(minerIndex < 0) {
      minerIndex = _minerIndexSearch(miner);
    }

    // The miner index still wasn't found. Must've been ended already?
    if(minerIndex < 0) {

      // Make sure the miner is old enough. 
      // pBTC.minerEnd does this for us with it's minerEnd function.
      uint256 servedDays = _currentDay() - miner.day;
      if (servedDays < _miningDuration()) {
        revert CannotEndMinerEarly(servedDays, _miningDuration());
      }

    } else {

      // End the miner as per usual
      pBTC.minerEnd(uint256(minerIndex), minerId, address(this));

    }

    _minerRemove(minerList[minerOwner], miner);

    return miner;

  }

  function _minerAt(uint256 index) internal view returns (MinerCache memory) {
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
    uint256 minerIndex,
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
    uint256 minerListLength = minerListRef.length;

    for(uint256 i=0; i < minerListLength;) {
      if(minerListRef[i].minerId == miner.minerId) {

        uint256 lastIndex = minerListLength - 1;

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

  // @notice Find the minerIndex of a miner. 
  // @dev Only accessible by passing -1 as the minerIndex.
  function _minerIndexSearch(
    MinerCache memory miner
  ) internal view returns (int) {
    uint256 minerListLength = pBTC.minerCount(address(this));
    int foundMinerIndex = -1;

    for(uint256 i=0; i < minerListLength;) {
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

  function minerCount(address minerAddress) external view returns (uint256) {
    return minerList[minerAddress].length;
  }

  function _miningDuration() internal pure returns (uint256) {
    return 30;
  }

  function _withdrawGracePeriod() internal pure returns (uint256) {
    return 30;
  }

  function _daysForPenalty() internal pure returns (uint256) {
    return _miningDuration() + _withdrawGracePeriod();
  }

  function _lastMinerIndex() internal view returns (uint256) {
    return pBTC.minerCount(address(this)) - 1;
  }

  function _currentDay() internal view returns (uint256) {
    return pBTC.currentDay();
  }
}
