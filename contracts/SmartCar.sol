pragma solidity ^0.4.4;

contract SmartCar {
  //The address of the car, which will sign transactions made by this contract.
  address public carSigner;

  // Value of the car, in wei
  uint public carValue;

  bytes32 public licensePlate;

  // Owners of the car, they will be the ones that receive payments from the car.
  // We assume each owner owns the car equally.
  address[] public owners;
  uint constant MAX_OWNERS = 100;

  //Earning from driving will be distributed to each owner for them to withdraw
  mapping (address => uint) public ownersBalance;
  uint public balanceToDistribute;

  uint constant INITIAL_CAR_SHARES = 100;
  mapping (address => uint) public carShares;

  DriverEntity currentDriverEntity;
  DriveStatus currentDriveStatus;

  //To keep track of who's currently using the car
  //If the owners are driving it, it will be their address.
  //If someone rented it, it will be the renter address, so he can be held accountable.
  //In this case, we could even ask for a warranty which will be sent back if the car is ok.
  address currentDriverAddress;
  uint currentDriveStartTime = 0;
  uint currentDriveRequiredEndTime = 0;

  //Rates
  uint constant RATE_DAILYRENTAL = 1 ether; //1 ETH

  enum DriverEntity {
    None,
    Owner,
    Autopilot,
    Cab,
    Uber,
    DailyRental,
    Other
  }

  enum DriveStatus {
    Idle,
    Driving,
    TurnedOff,
    Unavailable
  }

  bool carIsReady = false;

  // Somehow, the car should be able to communicate its "internals" to the contract.
  // These internals are the ones relevant to the functioning of the contract, such as it's fuel.
  // We don't care about oil or coolant for example, at this point at least.
  struct CarInternals {
    uint fuel; //Measured in percentage
  }

  CarInternals carInternals;

  modifier onlyIfReady {
        require(carIsReady);
        _;
    }

  event E_TransferEthForStipends(address _carSigner,uint _amount, uint indexed _eventDate);
  event E_RentCarDaily(address indexed _currentDriverAddress,uint _rentValue,uint _rentalStart,uint _rentalEnd);
  event E_EndRentCarDaily(address indexed _currentDriverAddress,uint _rentalEnd, bool _endedWithinPeriod);


  ////////////////////////////////////
  // Functions
  ////////////////////////////////////

  function SmartCar(bytes32 _licensePlate, uint _carValue) public {
    require(_licensePlate.length >0 && _carValue > 0);
    carSigner = msg.sender;
    carValue = _carValue;
    licensePlate = _licensePlate;
    carShares[address(this)] = INITIAL_CAR_SHARES;

    currentDriveStatus = DriveStatus.Idle;
    currentDriverEntity = DriverEntity.None;

    carInternals.fuel = 100;
  }

  //We will assume, for the time being, that the owners are set by the carSigner automatically,
  //and that they can't be changed.
  //We are basically doing the purchase of the car, off-chain.
  //We also assume that each person payed the same amount for the car, thus owning equal shares.
  function setOwners(address[] _owners) public {
    require(msg.sender == carSigner);
    require(_owners.length > 0 && _owners.length <= MAX_OWNERS);

    //Can only set owners once.
    require(owners.length == 0);

    owners = _owners;

    //We take the total carShares the "car" owns and we distribute them equally among new owners
    //If the shares are not properly divisible (I.E: 100 shares / 3 owners) the remaining shares stay with the car
    uint sharesToDistribute = carShares[address(this)]/owners.length;

    for (uint8 i; i<owners.length;i++){
      carShares[owners[i]] = sharesToDistribute;
      carShares[address(this)] -= sharesToDistribute;
    }

    carIsReady = true;
  }

  /////////////////////////////////////
  // Functions called by a third party
  /////////////////////////////////////

  // Anyone can rent the car for the day, as long as it is idle.
  // In real life, the workflow could be as follows:
  // 1. User calls this function from his mobile device or browser web3 dapp, sending the correct amount of eth
  // 2. The system generates a PIN number (we are just using his address as PIN right now)
  // 3. User gets on the car and unlocks it using the pin.

  // As it stands, we assume that the car, somehow recognizes that the user
  // that paid is actually in the car. We added a activateCar function that
  // acts as if it was a PIN.

  function rentCarDaily() public onlyIfReady payable{
    //No one must be using the car
    require (currentDriveStatus == DriveStatus.Idle);
    require (msg.value == RATE_DAILYRENTAL);

    currentDriverAddress = msg.sender;
    currentDriveStatus = DriveStatus.Driving;
    currentDriverEntity = DriverEntity.DailyRental;
    currentDriveStartTime = now;
    currentDriveRequiredEndTime = now + 1 days;

    balanceToDistribute += msg.value; // ADD SafeMath Library

    E_RentCarDaily(currentDriverAddress,msg.value, currentDriveStartTime,currentDriveRequiredEndTime);

    //TBD: What happens if the car is returned after the currentDriveRequiredEndTime has ended?
    // Charge more? Add driver to blacklist?
    //It should just stop working when the time has finished? We could have the car check every now and then.

  }

  // For the car to start it will ask the user for his PIN. Instead of generating a PIN
  // we are using his address as PIN, making sure they match.
  // This would be done in the car interface, of course it's a terrible user experience to as for an
  // address instead of a 4 digit PIN, but it will do for now.
  // We are not using this internally.

  function activateCar(address _user) public view onlyIfReady returns(bool){
    require (_user == currentDriverAddress);
    return true;
  }

  // This should be called by the end of the rental period.
  // Driver would tell the car to end the rental and the car would execute this function.
  // Also, the car can call it if the rental period ended. (This would be scheduled car-side)
  // Here, we distribute earnings and do the necessary cleanup such as
  // issuing fuel recharge if needed.
  function endRentCarDaily () public onlyIfReady {
    // The person renting the car can end the rental anytime.
    // The carSigner can end the rental only after the renting period has ended
    // in order to "claim the car back".
    require ((msg.sender == carSigner && now > currentDriveRequiredEndTime)
            || msg.sender == currentDriverAddress);

    //To be called only if it is being rented for the day.
    require (currentDriveStatus == DriveStatus.Driving);
    require (currentDriverEntity == DriverEntity.DailyRental);

    bool endedWithinPeriod = now <= currentDriveRequiredEndTime;

    E_EndRentCarDaily(currentDriverAddress, now, endedWithinPeriod);

    currentDriverAddress = address(0);
    currentDriveStatus = DriveStatus.Idle;
    currentDriverEntity = DriverEntity.None;
    currentDriveStartTime = 0;
    currentDriveRequiredEndTime = 0;

    //Distribute earnings of the car rental
    distributeEarnings();
  }

  /////////////////////////////////////
  // Functions called by the car itself
  /////////////////////////////////////

  // carSigner will need eth to pay for gas stipends being used throughout the day.
  // It should be able to get it from the car contract balance.
  // This would be called by the car automatically each day, for example.
  function triggerTransferEthForStipends() public onlyIfReady{
    require(msg.sender == carSigner);

    transferEthForStipends();
  }

  function transferEthForStipends() internal onlyIfReady {

    uint amount = 1 * (10 ** 17);  // 0.1 eth per day should be enough
    require (carSigner.balance < amount);
    require(balanceToDistribute >= amount);

    balanceToDistribute -= amount; // ADD SafeMath Library
    carSigner.transfer(amount);
    E_TransferEthForStipends(carSigner,amount, now);
  }

  //Distribute earnings to owners
  function distributeEarnings() internal onlyIfReady {
    //If the carSigner is running out of eth for transactions, transfer before distribution
    transferEthForStipends();

    //ETH should also be reserved for recharging fuel at a station. Not considered yet.
    //refuelCar();

    uint earningsPerOwner = balanceToDistribute / owners.length;
    for (uint8 i=0;i<owners.length;i++){
      ownersBalance[owners[i]] += earningsPerOwner; // ADD SafeMath Library
      balanceToDistribute -= earningsPerOwner; // ADD SafeMath Library
    }
  }

  /////////////////////////////////////
  // Functions called by owners
  /////////////////////////////////////

  // Allow an owner to manually distribute earnings, in case there is a pending
  // balance and the car has not ended a rental yet.
  function triggerDistributeEarnings() public onlyIfReady{
    require(balanceToDistribute >0);

    //Make sure the one calling the function is actually an owner
    bool isOwner = false;
    for (uint8 i=0;i<owners.length;i++){
      if (owners[i] == msg.sender){
        isOwner = true;
        break;
      }
    }
    require (isOwner);

    distributeEarnings();
  }

  //Each owner should call this function to withdraw the balance they have pending.
  function withdrawEarnings() public onlyIfReady{

    //Make sure the one calling the function is actually an owner
    bool isOwner = false;
    for (uint8 i=0;i<owners.length;i++){
      if (owners[i] == msg.sender){
        isOwner = true;
        break;
      }
    }
    require (isOwner);

    uint balanceToWithdraw = ownersBalance[msg.sender];
    require (balanceToWithdraw > 0);

    ownersBalance[msg.sender] =0;
    msg.sender.transfer(balanceToWithdraw);
  }

}
