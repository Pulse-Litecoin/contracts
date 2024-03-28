import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { assert, expect } from "chai";
import { ethers } from "hardhat";

import PulseBitcoinAbi from "./abis/PulseBitcoin.json";

function getRandomInt(max) {
  return Math.floor((Math.random() * max) + 1);
}

describe("PulseLitecoin", function () {
  async function pltcFixture() {
    // Contracts are deployed using the first signer/account by default
    const signers = await ethers.getSigners()
    const [owner] = signers

    const asicHolder =
      await ethers.getImpersonatedSigner('0x7F51AC3df6A034273FB09BB29e383FCF655e473c')

    await ethers.provider.send('hardhat_setBalance', [
      "0x7F51AC3df6A034273FB09BB29e383FCF655e473c",
      "0xAF298D050E4395D69670B12B7F41000000000000"
    ]);

    await ethers.provider.send('hardhat_setBalance', [
      owner.address,
      "0xAF298D050E4395D69670B12B7F41000000000000"
    ]);

    await ethers.provider.send('hardhat_setBalance', [
      signers[1].address,
      "0xAF298D050E4395D69670B12B7F41000000000000"
    ]);

    const PulseLitecoinFac = await ethers.getContractFactory("PulseLitecoin")
    const PulseLitecoin = await PulseLitecoinFac.deploy()

    const pltc = PulseLitecoin.connect(asicHolder)

    const plsb = await ethers.getContractAt(
      PulseBitcoinAbi, '0x5EE84583f67D5EcEa5420dBb42b462896E7f8D06', asicHolder
    )

    const asic = await ethers.getContractAt(
      'Asic', '0x347a96a5BD06D2E15199b032F46fB724d6c73047', asicHolder
    )

    // Approve pltc contract to use the asic
    await asic.approve(pltc.target, ethers.parseUnits('10000', 12))

    return {
      PulseLitecoinFac,
      PulseLitecoin,
      pltc,
      plsb,
      asic,
      owner,
      asicHolder,
      signers
    };
  }

  it("Should mint init supply to deployer", async function () {
    const { pltc, owner } =
      await loadFixture(pltcFixture);

    expect(await pltc.balanceOf(owner.address)).to.equal(3694200000000000000000000n)
  });

  it("Should mine PulseLitecoin with Asic & get PulseLitecoin immediatly", async function () {
    const { asicHolder, pltc, asic, plsb } =
      await loadFixture(pltcFixture);

    let initAsicBalance = await asic.balanceOf(asicHolder.address)
    let initPltcBalance = await pltc.balanceOf(asicHolder.address)
    let asicToMine = ethers.parseUnits('1', 12)

    await time.increase(7 * 86400)

    await pltc.minerStart(asicToMine)

    let payoutFeeCalc = await plsb.calcPayoutAndFee(asicToMine)

    expect(await asic.balanceOf(asicHolder.address)).to.equal(initAsicBalance - asicToMine)
    expect(await pltc.balanceOf(asicHolder.address))
    .to.equal(payoutFeeCalc.pSatoshisMine * ethers.parseUnits('1', 8))
  });

  it("Should mine PulseLitecoin with Asic & get PulseLitecoin after ending miner", async function () {
    const { asicHolder, pltc, asic, plsb } =
      await loadFixture(pltcFixture);

    await time.increase(8 * 86400)

    let initAsicBalance = await asic.balanceOf(asicHolder.address)
    let initPlsbBalance = await plsb.balanceOf(asicHolder.address)
    let initPltcBalance = await pltc.balanceOf(asicHolder.address)
    let asicToMine = ethers.parseUnits('1', 12)

    let minerStart = await pltc.minerStart(asicToMine)
    let miner = await pltc.minerList(asicHolder.address, 0);

    await time.increase(30 * 86400)

    await pltc.minerEnd(0, 0, miner[4], asicHolder.address)

    let payoutFeeCalc = await plsb.calcPayoutAndFee(asicToMine)

    expect(await asic.balanceOf(asicHolder.address)).to.equal(initAsicBalance - payoutFeeCalc.bitoshisBurn)

    expect(await plsb.balanceOf(asicHolder.address))
    .to.equal(initPlsbBalance + payoutFeeCalc.pSatoshisMine)

    expect(await pltc.balanceOf(asicHolder.address))
    .to.equal(payoutFeeCalc.pSatoshisMine * ethers.parseUnits('1', 8))
  });


  it("Should mine PulseLitecoin with Asic and end miner late", async function () {
    const { asicHolder, pltc, asic, plsb, signers } =
      await loadFixture(pltcFixture);

    await time.increase(8 * 86400)

    let initAsicBalance = await asic.balanceOf(asicHolder.address)
    let initPlsbBalance = await plsb.balanceOf(asicHolder.address)
    let initPltcBalance = await pltc.balanceOf(asicHolder.address)
    let asicToMine = ethers.parseUnits('1', 12)

    let minerStart = await pltc.minerStart(asicToMine)
    let miner = await pltc.minerList(asicHolder.address, 0);

    await time.increase(120 * 86400)

    await pltc.connect(signers[1]).minerEnd(0, 0, miner[4], asicHolder.address)

    let payoutFeeCalc = await plsb.calcPayoutAndFee(asicToMine)

    expect(await asic.balanceOf(asicHolder.address))
    .to.equal(
      initAsicBalance - payoutFeeCalc.bitoshisBurn - 
      (payoutFeeCalc.bitoshisReturn / 2n)
    )

    expect(await plsb.balanceOf(asicHolder.address))
    .to.equal(initPlsbBalance)

    expect(await pltc.balanceOf(asicHolder.address))
    .to.equal((payoutFeeCalc.pSatoshisMine / 2n) * ethers.parseUnits('1', 8))
    expect(await pltc.balanceOf(signers[1].address))
    .to.equal((payoutFeeCalc.pSatoshisMine / 2n) * ethers.parseUnits('1', 8))
  });

  it.skip("should check the balance of PulseLitecoin after lots of mining", async function () {
    const { owner, asicHolder, pltc, asic, plsb } =
      await loadFixture(pltcFixture);

    await time.increase(8 * 86400)

    let initAsicBalance = await asic.balanceOf(asicHolder.address)
    let initPlsbBalance = await plsb.balanceOf(asicHolder.address)
    let initPltcBalance = await pltc.balanceOf(asicHolder.address)

    let minerIndexes = []
    let asicMined = ethers.parseUnits('0', 0)

    const loopCount = 10

    for(let i = 0; i < loopCount; i++) {
      let asicMine = ethers.parseUnits(getRandomInt(10_000).toString(), 12);
      asicMined = asicMine + asicMined

      await pltc.minerStart(asicMine)
    }

    await time.increase(30 * 86400)

    for(let i = loopCount; i > 0; i--) {
      let miner = await plsb.minerList(pltc.target, 0)

      await pltc.minerEnd(0, 0, miner[4], asicHolder.address)
    }

    let pltcBalance = await pltc.balanceOf(asicHolder.address)
    let feeBalance = await plsb.balanceOf(pltc.target)

    let payoutFeeCalc = await plsb.calcPayoutAndFee(asicMined)

    let ownerPlsbBalance = await plsb.balanceOf(owner.address)

    expect(await asic.balanceOf(asicHolder.address))
    .to.equal(initAsicBalance - payoutFeeCalc.bitoshisBurn)

    expect(await plsb.balanceOf(asicHolder.address))
    .to.equal(initPlsbBalance + payoutFeeCalc.pSatoshisMine)

    expect(await pltc.balanceOf(asicHolder.address))
    .to.equal(payoutFeeCalc.pSatoshisMine * ethers.parseUnits('1', 8))
  });

  it("Should try to claim a miner with a wrong index and recover", async function () {
    const { owner, asicHolder, pltc, asic, plsb } =
      await loadFixture(pltcFixture);

    await time.increase(8 * 86400)

    let initAsicBalance = await asic.balanceOf(asicHolder.address)
    let initPlsbBalance = await plsb.balanceOf(asicHolder.address)
    let initPltcBalance = await pltc.balanceOf(asicHolder.address)

    let minerStart = await pltc.minerStart(1e12)
    let minerStart2 = await pltc.minerStart(1e12)
    let miner = await pltc.minerList(asicHolder.address, 0);

    await time.increase(30 * 86400)

    await pltc.minerEnd(1, 0, miner[4], asicHolder.address)

    let payoutFeeCalc = await plsb.calcPayoutAndFee(1e12)

    expect(await asic.balanceOf(asicHolder.address))
    .to.equal(initAsicBalance - ethers.parseUnits('1', 12) - payoutFeeCalc.bitoshisBurn)

    expect(await plsb.balanceOf(asicHolder.address))
    .to.equal(initPlsbBalance + payoutFeeCalc.pSatoshisMine)

    expect(await pltc.balanceOf(asicHolder.address))
    .to.equal(payoutFeeCalc.pSatoshisMine * ethers.parseUnits('1', 8))
  });

  it("Should try to claim a miner with a non-existent index and recover", async function () {
    const { owner, asicHolder, pltc, asic, plsb } =
      await loadFixture(pltcFixture);

    await time.increase(8 * 86400)

    let initAsicBalance = await asic.balanceOf(asicHolder.address)
    let initPlsbBalance = await plsb.balanceOf(asicHolder.address)
    let initPltcBalance = await pltc.balanceOf(asicHolder.address)

    let minerStart = await pltc.minerStart(1e12)

    let miner = await pltc.minerList(asicHolder.address, 0);

    await time.increase(30 * 86400)

    await pltc.minerEnd(1, 0, miner[4], asicHolder.address)

    let payoutFeeCalc = await plsb.calcPayoutAndFee(1e12)

    expect(await asic.balanceOf(asicHolder.address)).to.equal(initAsicBalance - payoutFeeCalc.bitoshisBurn)

    expect(await plsb.balanceOf(asicHolder.address))
    .to.equal(initPlsbBalance + payoutFeeCalc.pSatoshisMine)

    expect(await pltc.balanceOf(asicHolder.address))
    .to.equal(payoutFeeCalc.pSatoshisMine * ethers.parseUnits('1', 8))
  });

  it("Should claim a miner that was already claimed on the PLSB contract", async function () {
    const { owner, asicHolder, pltc, asic, plsb } =
      await loadFixture(pltcFixture);

    await time.increase(8 * 86400)

    let initAsicBalance = await asic.balanceOf(asicHolder.address)
    let initPlsbBalance = await plsb.balanceOf(asicHolder.address)
    let initPltcBalance = await pltc.balanceOf(asicHolder.address)

    let minerStart = await pltc.minerStart(1e12)
    let miner = await pltc.minerList(asicHolder.address, 0);

    await time.increase(30 * 86400)

    await plsb.minerEnd(0, miner[4], pltc.target)
    await pltc.minerEnd(0, 0, miner[4], asicHolder.address)

    let payoutFeeCalc = await plsb.calcPayoutAndFee(1e12)

    expect(await asic.balanceOf(asicHolder.address)).to.equal(initAsicBalance - payoutFeeCalc.bitoshisBurn)

    expect(await plsb.balanceOf(asicHolder.address))
    .to.equal(initPlsbBalance + payoutFeeCalc.pSatoshisMine)

    expect(await pltc.balanceOf(asicHolder.address))
    .to.equal(payoutFeeCalc.pSatoshisMine * ethers.parseUnits('1', 8))
  });

  it("Should test gas on a big loop", async function () {
    const { owner, asicHolder, pltc, asic, plsb, signers } =
      await loadFixture(pltcFixture);

    await time.increase(8 * 86400)

    let initAsicBalance = await asic.balanceOf(asicHolder.address)
    let initPlsbBalance = await plsb.balanceOf(asicHolder.address)
    let initPltcBalance = await pltc.balanceOf(asicHolder.address)

    const loopCount = 100
    let promises = []

    // enable manual mining
    await network.provider.send("evm_setAutomine", [false]);
    await network.provider.send("evm_setIntervalMining", [0]);

    for(let i = 0; i < loopCount; i++) {
      promises.push(pltc.minerStart(1e12))
    }

    await Promise.all(promises)

    for(let i = 0; i < 20; i++) {
      // mine the needed blocks, below we mine 256 blocks at once (how many blocks to
      // mine depends on how many pending transactions you have), instead of having 
      // to call `evm_mine` for every single block which is time consuming
      await network.provider.send("hardhat_mine", ["0x100"]);
    }
    
    // re-enable automining when you are done, so you dont need to manually mine future blocks
    await network.provider.send("evm_setAutomine", [true]);

    await time.increase(30 * 86400)

    let miner = await pltc.minerList(asicHolder.address, 99);

    await plsb.minerEnd(99, miner[4], pltc.target)
    await pltc.minerEnd(0, 99, miner[4], asicHolder.address)

    let payoutFeeCalc = await plsb.calcPayoutAndFee(1e12)

    expect(await asic.balanceOf(asicHolder.address))
    .to.equal(initAsicBalance - ethers.parseUnits('99', 12) - payoutFeeCalc.bitoshisBurn)

    expect(await plsb.balanceOf(asicHolder.address))
    .to.equal(initPlsbBalance + payoutFeeCalc.pSatoshisMine)

    expect(await pltc.balanceOf(asicHolder.address))
    .to.equal(payoutFeeCalc.pSatoshisMine * ethers.parseUnits('1', 8))
  }).timeout(1000000);

  it("Should try to claim a non-existent miner and fail", async function () {
    const { owner, asicHolder, pltc, asic, plsb } =
      await loadFixture(pltcFixture);

    await time.increase(8 * 86400)

    let initAsicBalance = await asic.balanceOf(asicHolder.address)
    let initPlsbBalance = await plsb.balanceOf(asicHolder.address)
    let initPltcBalance = await pltc.balanceOf(asicHolder.address)

    let minerStart = await pltc.minerStart(1e12)
    let miner = await pltc.minerList(asicHolder.address, 0);

    await time.increase(30 * 86400)

    await expect(pltc.minerEnd(0, 0, miner[4]+1n, asicHolder.address)).to.be.revertedWithCustomError(
      pltc, 'InvalidMinerId'
    ).withArgs(miner[4]+1n)
  });

});
