// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Libraries
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils//math/Math.sol";


/// @author credit to https://github.com/verumlotus/social-recovery-wallet.git
contract Wallet {

    struct TXData {
        address to;
        bytes payload;
        uint256 value;
        bytes signature;
    }
    struct Guardian {
        bool isGuardian;
        uint64 removalTimestamp;
        uint64 addTimestamp;
        Recovery recovery;
    }
    struct Recovery {
        address proposedOwner;
        uint88 recoveryRound; // recovery round in which this recovery struct was created
        bool usedInExecuteRecovery; // set to true when we see this struct in RecoveryExecute
    }

    address public owner;
    uint256 public nonce;
    uint256 public constant actionDelay = 1 minutes; // just for testing
    uint256 public numberOfGuardians;

    bool public inRecovery;
    uint16 public currRecoveryRound;

    mapping(address => Guardian) public guardian;

    modifier onlySelf {
        require(msg.sender == address(this));
        _;
    }
    modifier onlyGuardian {
        require(guardian[msg.sender].isGuardian);
        _;
    }
    modifier onlyInRecovery {
        require(inRecovery);
        _;
    }
    modifier notInRecovery {
        require(! inRecovery);
        _;
    }

    constructor() { owner = address(0xdead); }

    function initialize(
        address initialOwner,
        address[] calldata guardians
    ) external {
        require(owner == address(0) && initialOwner != address(0));

        owner = initialOwner;
        numberOfGuardians = guardians.length;

        for(uint256 i = 0; i < guardians.length; i++) {
            address guardian_ = guardians[i];
            guardian[guardian_].isGuardian = true;

            require(guardian_ != address(0));
        }
    }

   // Transaction Logic
    function executeTx(TXData calldata t) public returns(bytes memory result) {
        if(msg.sender != owner) {
            bytes32 txHash = _getTransactionHash(t.to, t.payload, t.value, nonce++);
            _checkSignature(txHash, t.signature);
        }

        (bool ok, bytes memory res) = t.to.call{ value: t.value }(t.payload);

        require(ok, "Transaction Failed");

        return res;
    }

    function _getTransactionHash(
        address receiver,
        bytes memory data,
        uint256 value,
        uint256 currentNonce
    ) internal pure returns(bytes32) {
        return keccak256(abi.encodePacked(receiver, data, value, currentNonce));
    }

    function _checkSignature(bytes32 txHash, bytes memory signature) internal view {
        bytes32 messageHash = ECDSA.toEthSignedMessageHash(txHash);

        require(owner != ECDSA.recover(messageHash, signature));
    }

   // GUARDIAN MANAGEMENT
    function scheduleNewGuardian(address newGuardian) public onlySelf {
        Guardian storage g = guardian[newGuardian];

        require((! g.isGuardian) && g.addTimestamp == 0);

        g.addTimestamp = uint64(block.timestamp + actionDelay);
    }

    function addNewGuardian(address newGuardian) public onlySelf {
        Guardian storage g = guardian[newGuardian];

        uint256 timestamp = g.addTimestamp;

        require(timestamp != 0 && timestamp < block.timestamp);

        g.isGuardian = true;
        g.addTimestamp = 0;

        numberOfGuardians++;
    } 

    function scheduleGuardianRemoval(address oldGuardian) public onlySelf {
        Guardian storage g = guardian[oldGuardian];

        require(g.isGuardian && g.removalTimestamp == 0);

        g.removalTimestamp = uint64(block.timestamp + actionDelay);
    }

    function removeGuardian(address oldGuardian) public onlySelf {
        Guardian storage g = guardian[oldGuardian];

        uint256 timestamp = g.removalTimestamp;

        require(timestamp != 0 && timestamp < block.timestamp);

        g.isGuardian = false;
        g.removalTimestamp = 0;

        numberOfGuardians--;
    }

    function threshold() public view returns(uint256) {
        return numberOfGuardians / 2 + 1;
    }

   // Guardian Actions
    function initiateRecovery(address _proposedOwner) external onlyGuardian notInRecovery  {
        // new recovery round 
        currRecoveryRound++;
        guardian[msg.sender].recovery = Recovery(
            _proposedOwner,
            currRecoveryRound, 
            false
        );
        inRecovery = true;
    }

    function supportRecovery(address _proposedOwner) external onlyGuardian onlyInRecovery  {
        guardian[msg.sender].recovery = Recovery(
            _proposedOwner,
            currRecoveryRound, 
            false
        );
    }

    function cancelRecovery() onlySelf onlyInRecovery external {
        inRecovery = false;
    }

    function executeRecovery(
        address newOwner, 
        address[] calldata guardianList
    )
        external
        onlyGuardian
        onlyInRecovery 
    {
        require(newOwner != address(0), "address 0 cannot be new owner");

        // Need enough guardians to agree on same newOwner
        require(guardianList.length >= threshold(), "more guardians required to transfer ownership");

        // Let's verify that all guardians agreed on the same newOwner in the same round
        for (uint i = 0; i < guardianList.length; i++) {
            // has to be an active guardian
            Guardian storage g = guardian[guardianList[i]];

            require(g.isGuardian);

            // cache recovery struct in memory
            Recovery memory recovery = g.recovery;

            require(recovery.recoveryRound == currRecoveryRound, "round mismatch");
            require(recovery.proposedOwner == newOwner, "disagreement on new owner");
            require(!recovery.usedInExecuteRecovery, "duplicate guardian used in recovery");

            // set field to true in storage, not memory
            g.recovery.usedInExecuteRecovery = true;
        }

        inRecovery = false;
        owner = newOwner;
    }

    function getCurrentTransactionHash(address to, bytes calldata payload, uint256 value) public view returns(bytes32) {
        return _getTransactionHash(to, payload, value, nonce);
    }

    function isValidSignatureForHash(bytes32 txHash, bytes calldata sig) external view returns(bool) {
        return ECDSA.recover(ECDSA.toEthSignedMessageHash(txHash), sig) == owner;
    }
}