// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const fs = require("fs");

async function main() {
  const [deployer] = await ethers.getSigners();

  // console.log("Deploying contracts with the account:", deployer.address);

  // console.log("Account balance:", (await deployer.getBalance()).toString());

  const Contract = await ethers.getContractFactory("HawdPool");
  const contract = await Contract.deploy();

  console.log("Contract address:", contract.address);

  // --------- Print address ---------------------
 
  fs.writeFileSync(
    "././contracts.js", `
    export const HawdPool = "${contract.address}"
    `
  )
}


// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
