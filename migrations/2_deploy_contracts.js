//var ConvertLib = artifacts.require("./ConvertLib.sol");
var SmartCar = artifacts.require("./SmartCar.sol");

module.exports = function(deployer) {
//  deployer.deploy(ConvertLib);
//  deployer.link(ConvertLib, MetaCoin);
  deployer.deploy(SmartCar,"",100);
};
