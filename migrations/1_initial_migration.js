const LaikaDog = artifacts.require("LaikaDog");
const DividendDistributor = artifacts.require("DividendDistributor");
module.exports = async function(deployer) {
  let dexRouter = "0x10ED43C718714eb63d5aA57B78B54704E256024E"; //router mainnet
  // let dexRouter = "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3"; //router testenet
  let laika = await deployer.deploy(LaikaDog, dexRouter);
  let contract_laika = await LaikaDog.deployed();
  await deployer.deploy(DividendDistributor, LaikaDog.address, LaikaDog.address);
  await DividendDistributor.deployed();
};
