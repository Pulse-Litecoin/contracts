// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

//        _   _____ ____
//  _ __ | | |_   _/ ___|
// | '_ \| |   | || |
// | |_) | |___| || |___
// | .__/|_____|_| \____|
// |_|
//
// t.me/pulselitecoin
// x.com/pulselitecoin

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./lib/PulseBitcoinMineable.sol";

contract PulseLitecoin is ERC20, ReentrancyGuard, PulseBitcoinMineable {
  uint private constant SCALE_FACTOR = 4;

  constructor() ERC20("PulseLitecoin", "pLTC") {}

  function decimals() public view virtual override returns (uint8) {
    return 12;
  }

  // @notice Start your miner
  // @param bitoshis The amount in ASIC to mine with
  function minerStart(uint bitoshis) external nonReentrant {
    ASIC.transferFrom(msg.sender, address(this), bitoshis);

    _minerStart(bitoshis);
  }

  // @notice End your miner
  // @param minerIndex The index of the miner on the pLTC contract
  // @param minerOwnerIndex The index of the miner on the minerOwner
  // @param minerId The minerId for the miner to end. Duh.
  // @param minerOwner The owner of the miner to end. Also Duh.
  function minerEnd(int minerIndex, uint minerOwnerIndex, uint minerId, address minerOwner) external nonReentrant {

    MinerCache memory miner = _minerEnd(minerIndex, minerOwnerIndex, minerId, minerOwner);

    uint servedDays = _currentDay() - miner.day;
    uint pltcMined = miner.pSatoshisMined * SCALE_FACTOR;

    // Any time after you end the miner, you can still mint pLTC.
    // If servedDays > _daysForPenalty(), The miner will lose all plsb and half asic as per the PulseBitcoin mining contract.
    // Added for pLTC, the miner loses half of the pLTC yield to the caller
    if (servedDays > _daysForPenalty()) {

      _mint(minerOwner, pltcMined / 2);
      _mint(msg.sender, pltcMined / 2);

      ASIC.transfer(minerOwner, miner.bitoshisReturned / 2);
      ASIC.transfer(msg.sender, miner.bitoshisReturned / 2);

    } else {

      _mint(minerOwner, pltcMined);

      ASIC.transfer(minerOwner, miner.bitoshisReturned);
      pBTC.transfer(minerOwner, miner.pSatoshisMined);

    }
  }
}
