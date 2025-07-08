/**
 * @title MAQXDistributor
 * @dev Upgradable contract for distributing MAQX tokens to ecosystem roles and pledge funds.
 * 
 * ✅ Current Features:
 * - Upgradable via Initializable + OwnableUpgradeable
 * - OnlyOwner access for all state-changing functions
 * - ERC20 MAQX token transfers for ecosystem and cause-specific funding
 * - Predefined shares for DAO, Dev, Rewards, Founder, and Global Mint
 * 
 * 🟡 Potential Future Improvements:
 * 1. Event Emissions: Improve observability of actions like `distributePayment`, `setPledgeFund`, etc.
 * 2. Distribution Trigger Logic: Decide if `distributeEcosystemShare()` should be:
 *    - Called from within `distributePayment()` OR
 *    - Exposed via a new public function like `triggerEcosystemDistribution()`
 * 3. Rescue Function: Add `rescueTokens()` for emergency token recovery.
 * 4. Fund Address Validation: Add a check to ensure `causeId` is registered (`!= address(0)`).
 * 5. Time Locks (Optional): Limit how frequently distribution can be executed.
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract MAQXDistributor is Initializable, OwnableUpgradeable {
    address public daoTreasuryWallet;
    address public developerPoolWallet;
    address public rewardFundWallet;
    address public founderWallet;
    address public globalMintWallet;
    IERC20 public maqxToken;

    address public ecosystemVaultAddress;
    mapping(uint256 => address) public pledgeFundByCause;

    function initialize(
        address _daoTreasuryWallet,
        address _developerPoolWallet,
        address _rewardFundWallet,
        address _founderWallet,
        address _globalMintWallet,
        address _maqxToken
    ) public initializer {
        __Ownable_init(msg.sender);
        daoTreasuryWallet = _daoTreasuryWallet;
        developerPoolWallet = _developerPoolWallet;
        rewardFundWallet = _rewardFundWallet;
        founderWallet = _founderWallet;
        globalMintWallet = _globalMintWallet;
        maqxToken = IERC20(_maqxToken);
    }

    function setEcosystemVaultAddress(address _addr) external onlyOwner{
        ecosystemVaultAddress = _addr;
    }

    function setPledgeFund(uint256 causeId, address fundAddr) external onlyOwner {
        pledgeFundByCause[causeId] = fundAddr;
    }

    function getPledgeFundAddress(uint256 causeId) public view returns (address) {
        return pledgeFundByCause[causeId];
    }

    function distributeEcosystemShare(uint256 amount) internal onlyOwner {
        uint256 daoShare = (amount * 3) / 10;
        uint256 devShare = (amount * 2) / 10;
        uint256 rewardShare = (amount * 2) / 10;
        uint256 founderShare = (amount * 2) / 10;
        uint256 mintShare = amount - (daoShare + devShare + rewardShare + founderShare); // 1%

        maqxToken.transfer(daoTreasuryWallet, daoShare);
        maqxToken.transfer(developerPoolWallet, devShare);
        maqxToken.transfer(rewardFundWallet, rewardShare);
        maqxToken.transfer(founderWallet, founderShare);
        maqxToken.transfer(globalMintWallet, mintShare);
    }

    function distributePayment(uint256 amount, uint256 causeId) external onlyOwner {
        uint256 toFund = (amount * 90) / 100;
        uint256 toEcosystem = amount - toFund;

        require(maqxToken.transfer(getPledgeFundAddress(causeId), toFund), "Pledge transfer failed");
        require(maqxToken.transfer(ecosystemVaultAddress, toEcosystem), "Ecosystem transfer failed");
    }
}