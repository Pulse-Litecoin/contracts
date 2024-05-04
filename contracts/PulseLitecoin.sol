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

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./lib/PulseBitcoinMineable.sol";

contract PulseLitecoin is ERC20, ReentrancyGuard, PulseBitcoinMineable {
  address private constant DEAD_ADDRESS = address(0x0000000000000000000000000000000000000000);

  uint private constant SCALE_FACTOR = 1e8;
  uint private constant MINING_ADVANCE_PERIOD = 7;
  uint public immutable START_DAY;

  mapping(address => bool) public preMiners;

  constructor() ERC20("PulseLitecoin", "pLTC") {
    START_DAY = _currentDay();
  }

  function minerStart(uint bitoshis) external nonReentrant {
    ASIC.transferFrom(msg.sender, address(this), bitoshis);

    MinerCache memory miner = _minerStart(bitoshis);

    // If this is the first week of mining, mint pLTC now
    if(_currentDay() - START_DAY <= MINING_ADVANCE_PERIOD) {
      _mint(msg.sender, miner.pSatoshisMined * SCALE_FACTOR);
      preMiners[msg.sender] = true;
    }
  }

  function minerEnd(int minerIndex, uint minerOwnerIndex, uint minerId, address minerOwner) external nonReentrant {

    MinerCache memory miner = _minerEnd(minerIndex, minerOwnerIndex, minerId, minerOwner);

    uint servedDays = _currentDay() - miner.day;
    uint cryptoCoinMined = miner.pSatoshisMined * SCALE_FACTOR;

    // Any time after you end the miner, you can still mint pLTC.
    // If servedDays > _daysForPenalty(), The miner will lose all plsb and half asic as per the PulseBitcoin mining contract.
    // Also, the miner loses half of the pLTC yield to the caller
    if (servedDays > _daysForPenalty()) {

      if(!preMiners[minerOwner]) {
        _mint(minerOwner, cryptoCoinMined / 2);
        _mint(msg.sender, cryptoCoinMined / 2);
      }

      ASIC.transfer(minerOwner, miner.bitoshisReturned / 2);
      ASIC.transfer(msg.sender, miner.bitoshisReturned / 2);

    } else {

      if(!preMiners[minerOwner]) {
        _mint(minerOwner, cryptoCoinMined);
      }

      ASIC.transfer(minerOwner, miner.bitoshisReturned);
      PLSB.transfer(minerOwner, miner.pSatoshisMined);

    }
  }
}
