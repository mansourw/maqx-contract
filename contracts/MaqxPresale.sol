// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract MaqxPresale {
    address public owner;
    IERC20 public maqxToken;
    IERC20 public usdtToken;
    AggregatorV3Interface public ethUsdPriceFeed;

    uint256 public constant PRICE_PER_MAQX_USDT = 10 ** 17; // 0.10 USDT
    uint256 public maxTokensForSale = 20_000_000 * 10 ** 18;
    uint256 public tokensSold;
    mapping(address => uint256) public purchasedAmount;
    uint256 public constant MAX_PER_WALLET = 100_000 * 10 ** 18; // 100k MAQX per wallet

    mapping(address => uint256) public whitelist;

    event PurchasedWithUSDT(address indexed buyer, uint256 usdtAmount, uint256 maqxAmount);
    event PurchasedWithETH(address indexed buyer, uint256 ethAmount, uint256 maqxAmount);
    event LogPresaleBuyer(address indexed buyer, uint256 amount);

    constructor(
        address _maqxToken,
        address _usdtToken,
        address _ethUsdPriceFeed
    ) {
        _setOwner(msg.sender);
        _setTokens(_maqxToken, _usdtToken);
        _setPriceFeed(_ethUsdPriceFeed);
    }

    function _setOwner(address _owner) private {
        owner = _owner;
    }

    function _setTokens(address _maqxToken, address _usdtToken) private {
        maqxToken = IERC20(_maqxToken);
        usdtToken = IERC20(_usdtToken);
    }

    function _setPriceFeed(address _ethUsdPriceFeed) private {
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
    }

    function _getLatestEthPrice() internal view returns (uint256) {
        (, int256 price,,,) = ethUsdPriceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function buyWithUSDT(uint256 usdtAmount) external {
        require(usdtAmount > 0, "Zero amount");

        uint256 numerator = usdtAmount * 1e18;
        uint256 maqxAmount = numerator / PRICE_PER_MAQX_USDT;

        uint256 currentSold = tokensSold;
        uint256 newTotalSold = currentSold + maqxAmount;
        require(newTotalSold <= maxTokensForSale, "Cap exceeded");

        uint256 userCap = whitelist[msg.sender] > 0 ? whitelist[msg.sender] : MAX_PER_WALLET;

        uint256 currentUserTotal = purchasedAmount[msg.sender];
        uint256 newUserTotal = currentUserTotal + maqxAmount;
        require(newUserTotal <= userCap, "Wallet cap exceeded");

        tokensSold = newTotalSold;
        purchasedAmount[msg.sender] = newUserTotal;

        require(usdtToken.transferFrom(msg.sender, owner, usdtAmount), "USDT transfer failed");
        require(maqxToken.transferFrom(owner, msg.sender, maqxAmount), "MAQX transfer failed");

        emit PurchasedWithUSDT(msg.sender, usdtAmount, maqxAmount);
        emit LogPresaleBuyer(msg.sender, maqxAmount);
    }

    function getMaqxAmountFromEth(uint256 ethAmount) internal view returns (uint256) {
        uint256 ethPrice = _getLatestEthPrice();
        uint256 ethUsdValue = (ethPrice * ethAmount) / 1e8;
        return (ethUsdValue * 1e18) / PRICE_PER_MAQX_USDT;
    }

    function validatePurchase(address buyer, uint256 maqxAmount) internal view {
        uint256 newTotalSold = tokensSold + maqxAmount;
        require(newTotalSold <= maxTokensForSale, "Cap exceeded");

        uint256 userCap = whitelist[buyer] > 0 ? whitelist[buyer] : MAX_PER_WALLET;
        uint256 newUserTotal = purchasedAmount[buyer] + maqxAmount;
        require(newUserTotal <= userCap, "Wallet cap exceeded");
    }

    function buyWithETH() external payable {
        uint256 ethAmount = msg.value;
        require(ethAmount > 0, "Zero ETH");

        uint256 maqxAmount = getMaqxAmountFromEth(ethAmount);
        validatePurchase(msg.sender, maqxAmount);

        tokensSold += maqxAmount;
        purchasedAmount[msg.sender] += maqxAmount;

        (bool sent, ) = payable(owner).call{value: ethAmount}("");
        require(sent, "ETH transfer failed");

        require(maqxToken.transferFrom(owner, msg.sender, maqxAmount), "MAQX transfer failed");

        emit PurchasedWithETH(msg.sender, ethAmount, maqxAmount);
        emit LogPresaleBuyer(msg.sender, maqxAmount);
    }

    function updatePriceFeed(address newFeed) external onlyOwner {
        ethUsdPriceFeed = AggregatorV3Interface(newFeed);
    }

    function updateMaxTokensForSale(uint256 newMax) external onlyOwner {
        maxTokensForSale = newMax;
    }

    function rescueTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }

    function setWhitelist(address buyer, uint256 customCap) external onlyOwner {
        whitelist[buyer] = customCap;
    }
}