import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("PulseLitecoin", (m) => {
  const pltc = m.contract("PulseLitecoin");

  return { pltc };
});