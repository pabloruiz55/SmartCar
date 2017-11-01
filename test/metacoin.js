var SmartCar = artifacts.require("./SmartCar.sol");

contract('SmartCar', function(accounts) {
  it("should initialize properly", function() {
    return SmartCar.deployed().then(function(instance) {
      //return instance.getBalance.call(accounts[0]);
      return instance.carValue.call();
    }).then(function(carValue) {
      assert.equal(carValue, 1000, "Value should be 1000");
    });
  });
  it("should initialize properly 2", function() {
    return SmartCar.deployed().then(function(instance) {
      //return instance.getBalance.call(accounts[0]);
      return instance.licensePlate.call();
    }).then(function(licensePlate) {
      assert.notEqual(licensePlate, "", "Should provide license plate");
    });
  });
});
