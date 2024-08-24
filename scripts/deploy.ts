import { ethers } from "hardhat"

async function main() {
  const PulseLitecoinFac = await ethers.getContractFactory("PulseLitecoin")
  const pulseLitecoin = await PulseLitecoinFac.deploy()

  console.log(`Deployed @ ${pulseLitecoin.target}`)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
