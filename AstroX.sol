/*
 * AstroX
 *
 * Written by: MrGreenCrypto
 * Co-Founder of CodeCraftrs.com
 * 
 * SPDX-License-Identifier: None
 */

pragma solidity 0.8.17;

interface IBEP20 {
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address _owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount ) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IDEXPair {
    function sync() external;
}

interface IDEXRouter {
    function factory() external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn, 
        uint256 amountOutMin, 
        address[] calldata path, 
        address to, 
        uint256 deadline
    ) external;
}

interface IPrivateStakingPool {
    function depositPrivateStakingAmounts(address[] memory wallets) external returns(uint256);
    function whitelistWhalesForStaking(address[] memory wallets) external;
}

contract PrivateStakingPool {
	address public atx; 
	uint256 public totalStakers; 
    uint256 public totalRewardsPerStaker;
    uint256 public stakingAmount;
    uint256 private veryBigNumber = 10 ** 36;
    uint256 public timeOfLaunch;
    mapping (address => uint256) public claimedRewards;
    mapping (address => uint256) public excludedRewards;
	mapping (address => uint256) public deposits;
    mapping (address => bool) public excluded;
    mapping (address => bool) public whitelisted;
    mapping (address => bool) public stakedLater;

	event Unstaked(address indexed redeemer, uint256 quantity);

    modifier onlyAtx(){
        require (msg.sender == atx, "Only the CEO can do that");
        _;
    }

	constructor(uint256 tokenAmount, uint256 launchTime) {
        atx = msg.sender;
        timeOfLaunch = launchTime;
        stakingAmount = tokenAmount;
    }

    receive() external payable {
        totalRewardsPerStaker += msg.value * veryBigNumber / totalStakers;
    }

    function depositPrivateStakingAmounts(address[] memory wallets) external onlyAtx returns(uint256) {
        if(totalStakers != 0) return 0;
        uint256 totalWallets = wallets.length;
        totalStakers = totalWallets;
        for(uint i = 0; i<totalWallets;i++){
            deposits[wallets[i]] = stakingAmount;
        }
        return totalWallets * stakingAmount;
    }

    function whitelistWhalesForStaking(address[] memory wallets) external onlyAtx {
        uint256 totalWallets = wallets.length;
        totalStakers = totalWallets;
        for(uint i = 0; i<totalWallets;i++){
            whitelisted[wallets[i]] = true;
        }
    }

    function checkLockedTokens() internal view returns(uint256) {
        uint256 weeksSinceLaunch = (block.timestamp - timeOfLaunch) / 7 days;
        uint256 lockedAmount = weeksSinceLaunch > 9 ? 0 : stakingAmount * (9 - weeksSinceLaunch) / 10;
        return lockedAmount;
    }

    function stake() external {
        if(totalStakers >= 30 || deposits[msg.sender] > 0 || !whitelisted[msg.sender]) return;
        if(excluded[msg.sender]) excluded[msg.sender] = false;
        IBEP20(atx).transferFrom(msg.sender, address(this), stakingAmount);
        totalStakers++;
        deposits[msg.sender] = stakingAmount;
        excludedRewards[msg.sender] = totalRewardsPerStaker;
        stakedLater[msg.sender] = true;
    }

	function unstake() external {
		uint256 amount = deposits[msg.sender];
        uint256 lockedTokens = checkLockedTokens();
        if(stakedLater[msg.sender]) lockedTokens = 0;
		amount -= lockedTokens;
        if(amount == 0) return;
        _claim(msg.sender);
		IBEP20(atx).transfer(msg.sender, amount);
		
        if(!excluded[msg.sender]) {
            totalStakers--;
            excluded[msg.sender] = true;
        }

		deposits[msg.sender] -= amount;
		emit Unstaked(msg.sender, amount);
	}

    function claimRewards() external {
        _claim(msg.sender);
    }

    function _claim(address staker) internal {
        uint256 claimedAlready = excludedRewards[staker];
        if(excluded[staker]) return;
        if(claimedAlready >= totalRewardsPerStaker) return;
        uint256 claimableNow = (totalRewardsPerStaker - claimedAlready) / veryBigNumber;
        payable(staker).transfer(claimableNow);
        claimedRewards[staker] += claimableNow;
        excludedRewards[staker] = totalRewardsPerStaker;
    }
}

interface IPublicStakingPool {
    function depositPublicStakingAmounts(address[] memory wallets) external returns(uint256);
}

contract PublicStakingPool {
	address public atx;
    uint256 public constant MAX_POOL = 1_000_000_000 * 10**18;
	uint256 public totalTokensInPool;
    uint256 public totalRewardsPerToken;
    uint256 private veryBigNumber = 10 ** 36;
    mapping (address => uint256) public claimedRewards;
	mapping (address => uint256) public deposits;
    mapping (address => uint256) public excluded;
	event Unstaked(address indexed staker, uint256 quantity, uint256 stakeableTokens);
    event Staked(address indexed staker, uint256 quantity, uint256 stakeableTokens);

    modifier onlyAtx(){
        require (msg.sender == atx, "Only the CEO can do that");
        _;
    }

	constructor() {
        atx = msg.sender;
    }

    receive() external payable {
        totalRewardsPerToken += msg.value * veryBigNumber / totalTokensInPool;
    }

    function depositPublicStakingAmounts(address[] memory wallets, uint256[] memory amounts) external onlyAtx returns(uint256) {
        uint256 totalWallets = wallets.length;
        uint256 totalDeposits;
        
        for(uint i = 0; i<totalWallets;i++){
            deposits[wallets[i]] = amounts[i];
            totalDeposits += amounts[i];
        }

        totalTokensInPool += totalDeposits;
        return totalDeposits;
    }

	function unstake() external {
		uint256 amount = deposits[msg.sender];
        if(amount == 0) return;
        _claim(msg.sender);
		IBEP20(atx).transfer(msg.sender, amount);
        totalTokensInPool -= amount;
		deposits[msg.sender] = 0;
		emit Unstaked(msg.sender, amount, MAX_POOL - totalTokensInPool);
	}

    function stake(uint256 amount) external {
        if(totalTokensInPool == MAX_POOL) return;
        if(totalTokensInPool + amount > MAX_POOL) amount = MAX_POOL - totalTokensInPool;
        if(deposits[msg.sender] > 0) _claim(msg.sender);
        deposits[msg.sender] += amount;
        totalTokensInPool += amount;
        excluded[msg.sender] = totalRewardsPerToken;
        IBEP20(atx).transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount, MAX_POOL - totalTokensInPool);
    }

    function claimRewards() external {
        _claim(msg.sender);
    }

    function _claim(address staker) internal {
        uint256 claimedAlready = excluded[staker];
        if(claimedAlready >= totalRewardsPerToken * deposits[staker]) return;
        uint256 claimableNow = deposits[staker] * (totalRewardsPerToken - claimedAlready) / veryBigNumber;
        payable(staker).transfer(claimableNow);
        claimedRewards[staker] += claimableNow;
        excluded[staker] = totalRewardsPerToken;
    }
}

contract AstroX is IBEP20 {
    string constant _name = "AstroX";
    string constant _symbol = "ATX";
    uint8 constant _decimals = 18;
    uint256 _totalSupply = 400_000_000_000 * (10**_decimals);

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) public limitless;

    IDEXRouter public constant ROUTER = IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address public constant CEO = 0xe6497e1F2C5418978D5fC2cD32AA23315E7a41Fb;
    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    address immutable pool1;
    address immutable pool2;
    address immutable pool3;
    address immutable pool4;
    address immutable pool5;
    
    address public marketingWallet = 0xe6497e1F2C5418978D5fC2cD32AA23315E7a41Fb;
    address public tokenWallet = 0xe6497e1F2C5418978D5fC2cD32AA23315E7a41Fb;
    address public immutable pcsPair;
    address[] public pairs;

    modifier onlyCEO(){
        require (msg.sender == CEO, "Only the CEO can do that");
        _;
    }

    event WalletsChanged(address marketingWallet, address tokenWallet);
    event TokenRescued(address tokenRescued, uint256 amountRescued);
    event BnbRescued(uint256 balanceRescued);
    event ExcludedAddressFromTax(address wallet);
    event UnExcludedAddressFromTax(address wallet);
    event AirdropsSent(address[] airdropWallets, uint256[] amount);
    event TokensSwappedForBnb(uint256 bnbReceived);

    constructor(uint256 launchTime) {
        pcsPair = IDEXFactory(IDEXRouter(ROUTER).factory()).createPair(WBNB, address(this));
        pairs.push(pcsPair);
        _allowances[address(this)][address(ROUTER)] = type(uint256).max;

        limitless[CEO] = true;
        limitless[address(this)] = true;

        pool1 = address(new PrivateStakingPool(16666665 * 10**_decimals, launchTime));
        pool2 = address(new PrivateStakingPool(83333325 * 10**(_decimals-1), launchTime));
        pool3 = address(new PrivateStakingPool(5555555 * 10**_decimals, launchTime));
        pool4 = address(new PrivateStakingPool(27777775 * 10**(_decimals-1), launchTime));
        pool5 = address(new PublicStakingPool());

        _balances[CEO] = _totalSupply;
        emit Transfer(address(0), CEO, _totalSupply);
    }

    receive() external payable {}
    function name() public pure override returns (string memory) {return _name;}
    function totalSupply() public view override returns (uint256) {return _totalSupply;}
    function decimals() public pure override returns (uint8) {return _decimals;}
    function symbol() public pure override returns (string memory) {return _symbol;}
    function balanceOf(address account) public view override returns (uint256) {return _balances[account];}
    function allowance(address holder, address spender) public view override returns (uint256) {return _allowances[holder][spender];}
    function approveMax(address spender) external returns (bool) {return approve(spender, type(uint256).max);}
    function transfer(address recipient, uint256 amount) external override returns (bool) {return _transferFrom(msg.sender, recipient, amount);}
    
    function approve(address spender, uint256 amount) public override returns (bool) {
        require(spender != address(0), "Can't use zero address here");
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        require(spender != address(0), "Can't use zero address here");
        _allowances[msg.sender][spender]  = allowance(msg.sender, spender) + addedValue;
        emit Approval(msg.sender, spender, _allowances[msg.sender][spender]);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        require(spender != address(0), "Can't use zero address here");
        require(allowance(msg.sender, spender) >= subtractedValue, "Can't subtract more than current allowance");
        _allowances[msg.sender][spender]  = allowance(msg.sender, spender) - subtractedValue;
        emit Approval(msg.sender, spender, _allowances[msg.sender][spender]);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount ) external override returns (bool) {
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            require(_allowances[sender][msg.sender] >= amount, "Insufficient Allowance");
            _allowances[sender][msg.sender] -= amount;
            emit Approval(sender, msg.sender, _allowances[sender][msg.sender]);
        }
        
        return _transferFrom(sender, recipient, amount);
    }

    function setAstroXWallets(address marketingAddress, address tokenAddress) external onlyCEO {
        require(marketingAddress != address(0) && tokenAddress != address(0), "Can't use zero addresses here");
        marketingWallet = marketingAddress;
        tokenWallet = tokenAddress;
        emit WalletsChanged(marketingWallet, tokenWallet);
    }

    function rescueAnyToken(address tokenToRescue) external onlyCEO {
        require(tokenToRescue != address(this), "Can't rescue your own");
        emit TokenRescued(tokenToRescue, IBEP20(tokenToRescue).balanceOf(address(this)));
        IBEP20(tokenToRescue).transfer(msg.sender, IBEP20(tokenToRescue).balanceOf(address(this)));
    }

    function rescueBnb() external onlyCEO {
        emit BnbRescued(address(this).balance);
        payable(msg.sender).transfer(address(this).balance);
    }

    function setAddressTaxStatus(address wallet, bool status) external onlyCEO {
        limitless[wallet] = status;
        if(status) emit ExcludedAddressFromTax(wallet);
        else emit UnExcludedAddressFromTax(wallet);
    }

    function addPair(address pairToAdd) external onlyCEO {
        pairs.push(pairToAdd);
    }

    function removeLastPair() external onlyCEO {
        if(pairs.length == 1) return;
        pairs.pop();
    }

    function airdropToWallets(address[] memory airdropWallets, uint256[] memory amount) external onlyCEO {
        require(airdropWallets.length == amount.length,"Arrays must be the same length");
        require(airdropWallets.length <= 200,"Wallets list length must be <= 200");
        for (uint256 i = 0; i < airdropWallets.length; i++) {
            address wallet = airdropWallets[i];
            uint256 airdropAmount = amount[i] * (10**_decimals);
            _lowGasTransfer(msg.sender, wallet, airdropAmount);
        }
        emit AirdropsSent(airdropWallets, amount);
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        if (limitless[sender] || limitless[recipient]) return _lowGasTransfer(sender, recipient, amount);
        amount = takeTax(sender, recipient, amount);

        return _lowGasTransfer(sender, recipient, amount);
    }

    function takeTax(address sender, address recipient, uint256 amount) internal returns (uint256) {
        uint256 taxAmount;
        if(isPair(sender)) {
            taxAmount = amount * 7 / 100;
            _lowGasTransfer(sender, pcsPair, taxAmount / 7);
            _lowGasTransfer(sender, address(this), taxAmount * 6 / 7);
            return amount - taxAmount;
        }

        if(isPair(recipient)) {
             taxAmount = amount * 7 / 100;
            _lowGasTransfer(sender, pcsPair, taxAmount / 7);
            _lowGasTransfer(sender, address(this), taxAmount * 6 / 7);
            if(balanceOf(address(this)) > 0) swapAstroX();
            return amount - taxAmount;
        }

        return amount - taxAmount;
    }

    function isPair(address check) internal view returns(bool) {
        for (uint256 i = 0; i < pairs.length; i++) if(check == pairs[i]) return true;
        return false;
    }

    function _lowGasTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(sender != address(0) && recipient != address(0), "Can't use zero addresses here");
        require(amount <= _balances[sender], "Can't transfer more than you own");
        if(amount == 0) return true;
        _balances[sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function swapAstroX() internal {
        uint256 contractBalance = _balances[address(this)];
        if(contractBalance == 0) return;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

        ROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(
            contractBalance,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 bnbToPayOut = address(this).balance;
        bool success;
        (success,) = address(pool1).call{value: bnbToPayOut / 6}("");
        (success,) = address(pool2).call{value: bnbToPayOut / 12}("");
        (success,) = address(pool3).call{value: bnbToPayOut / 20}("");
        (success,) = address(pool4).call{value: bnbToPayOut / 30}("");
        (success,) = address(pool5).call{value: bnbToPayOut / 6}("");
        (success,) = address(marketingWallet).call{value: address(this).balance}("");
        if(success) emit TokensSwappedForBnb(bnbToPayOut);
    }

    function depositPool1(address[] memory wallets) external onlyCEO {
        uint256 totalDeposits = IPrivateStakingPool(pool1).depositPrivateStakingAmounts(wallets);
        _lowGasTransfer(msg.sender, pool1, totalDeposits);
    }
    
    function depositPool2(address[] memory wallets) external onlyCEO {
        uint256 totalDeposits = IPrivateStakingPool(pool2).depositPrivateStakingAmounts(wallets);
        _lowGasTransfer(msg.sender, pool2, totalDeposits);
    }
    
    function depositPool3(address[] memory wallets) external onlyCEO {
        uint256 totalDeposits = IPrivateStakingPool(pool3).depositPrivateStakingAmounts(wallets);
        _lowGasTransfer(msg.sender, pool3, totalDeposits);
    }
    
    function depositPool4(address[] memory wallets) external onlyCEO {
        uint256 totalDeposits = IPrivateStakingPool(pool4).depositPrivateStakingAmounts(wallets);
        _lowGasTransfer(msg.sender, pool4, totalDeposits);
    }
    
    function depositPool5(address[] memory wallets) external onlyCEO {
        uint256 totalDeposits = IPublicStakingPool(pool5).depositPublicStakingAmounts(wallets);
        _lowGasTransfer(msg.sender, pool5, totalDeposits);
    }

    function whitelistWhalesForStakingInPool1(address[] memory wallets) external onlyCEO {
        IPrivateStakingPool(pool1).whitelistWhalesForStaking(wallets);
    }

    function whitelistWhalesForStakingInPool2(address[] memory wallets) external onlyCEO {
        IPrivateStakingPool(pool2).whitelistWhalesForStaking(wallets);
    }

    function whitelistWhalesForStakingInPool3(address[] memory wallets) external onlyCEO {
        IPrivateStakingPool(pool3).whitelistWhalesForStaking(wallets);
    }

    function whitelistWhalesForStakingInPool4(address[] memory wallets) external onlyCEO {
        IPrivateStakingPool(pool4).whitelistWhalesForStaking(wallets);
    }
}