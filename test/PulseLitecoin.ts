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
    await asic.approve(pltc.target, ethers.parseUnits('1000000', 12))

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

  it("Should mine PulseLitecoin with Asic & get PulseLitecoin immediatly (early bird)", async function () {
    const { asicHolder, pltc, asic, plsb } =
      await loadFixture(pltcFixture);

    let initAsicBalance = await asic.balanceOf(asicHolder.address)
    let initPltcBalance = await pltc.balanceOf(asicHolder.address)
    let asicToMine = ethers.parseUnits('1', 12)

    await time.increase(7 * 86400)

    await pltc.minerStart(asicToMine)
    let miner = await pltc.minerList(asicHolder.address, 0)

    let payoutFeeCalc = await plsb.calcPayoutAndFee(asicToMine)

    expect(await asic.balanceOf(asicHolder.address)).to.equal(initAsicBalance - asicToMine)
    expect(await pltc.balanceOf(asicHolder.address))
    .to.equal(payoutFeeCalc.pSatoshisMine * ethers.parseUnits('1', 3))

    await time.increase(30 * 86400)

    await pltc.minerEnd(0, 0, miner[4], asicHolder.address)

    expect(await asic.balanceOf(asicHolder.address)).to.equal(initAsicBalance - payoutFeeCalc.bitoshisBurn)
    expect(await pltc.balanceOf(asicHolder.address))
    .to.equal(payoutFeeCalc.pSatoshisMine * ethers.parseUnits('1', 3))
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
    .to.equal(payoutFeeCalc.pSatoshisMine * ethers.parseUnits('1', 3))
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
    .to.equal((payoutFeeCalc.pSatoshisMine / 2n) * ethers.parseUnits('1', 3))
    expect(await pltc.balanceOf(signers[1].address))
    .to.equal((payoutFeeCalc.pSatoshisMine / 2n) * ethers.parseUnits('1', 3))
  });

  it("Should check the balance of PulseLitecoin after lots of mining", async function () {
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
      let asicMine = ethers.parseUnits(getRandomInt(1_000).toString(), 12);
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
    .to.equal(payoutFeeCalc.pSatoshisMine * ethers.parseUnits('1', 3))

    expect(await asic.balanceOf(pltc.target)).to.equal(0)
    expect(await plsb.balanceOf(pltc.target)).to.equal(0)
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
    await pltc.minerEnd(-1, 0, miner[4], asicHolder.address)

    let payoutFeeCalc = await plsb.calcPayoutAndFee(1e12)

    expect(await asic.balanceOf(asicHolder.address)).to.equal(initAsicBalance - payoutFeeCalc.bitoshisBurn)

    expect(await plsb.balanceOf(asicHolder.address))
    .to.equal(initPlsbBalance + payoutFeeCalc.pSatoshisMine)

    expect(await pltc.balanceOf(asicHolder.address))
    .to.equal(payoutFeeCalc.pSatoshisMine * ethers.parseUnits('1', 3))
  });

  it("Should claim a miner with unknown minerIndex (large dataset)", async function () {
    const { owner, asicHolder, pltc, asic, plsb } =
      await loadFixture(pltcFixture);

    await time.increase(8 * 86400)

    const loopCount = 100

    for(let i = 0; i < loopCount; i++) {
      let asicMine = ethers.parseUnits(getRandomInt(100).toString(), 12);

      await pltc.minerStart(asicMine)
    }

    let initAsicBalance = await asic.balanceOf(asicHolder.address)
    let initPlsbBalance = await plsb.balanceOf(asicHolder.address)
    let initPltcBalance = await pltc.balanceOf(asicHolder.address)

    let minerStart = await pltc.minerStart(1e12)
    let miner = await pltc.minerList(asicHolder.address, loopCount);

    await time.increase(30 * 86400)

    await pltc.minerEnd(-1, loopCount, miner[4], asicHolder.address)

    let payoutFeeCalc = await plsb.calcPayoutAndFee(1e12)

    expect(await asic.balanceOf(asicHolder.address)).to.equal(initAsicBalance - payoutFeeCalc.bitoshisBurn)

    expect(await plsb.balanceOf(asicHolder.address))
    .to.equal(initPlsbBalance + payoutFeeCalc.pSatoshisMine)

    expect(await pltc.balanceOf(asicHolder.address))
    .to.equal(payoutFeeCalc.pSatoshisMine * ethers.parseUnits('1', 3))
  });

  it("Should try to claim a invalid minerId and fail", async function () {
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

  it("Should try to claim without minerIndex with invalid minerId and fail", async function () {
    const { owner, asicHolder, pltc, asic, plsb } =
      await loadFixture(pltcFixture);

    await time.increase(8 * 86400)

    let minerStart = await pltc.minerStart(1e12)
    let miner = await pltc.minerList(asicHolder.address, 0);

    await time.increase(30 * 86400)

    await expect(pltc.minerEnd(-1, 0, miner[4]+1n, asicHolder.address)).to.be.revertedWithCustomError(
      pltc, 'InvalidMinerId'
    ).withArgs(miner[4]+1n)
  });

});
