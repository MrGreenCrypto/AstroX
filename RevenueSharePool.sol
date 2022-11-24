
/*
 * AstroX Revenue Sharing Pool
 *
 * Written by: MrGreenCrypto
 * Co-Founder of CodeCraftrs.com
 * 
 * SPDX-License-Identifier: None
 */

pragma solidity 0.8.17;

interface IBEP20 {
    function balanceOf(address account) external view returns (uint256);
}

contract RevenueSharePool {
    address public constant atx = 0xe6497e1F2C5418978D5fC2cD32AA23315E7a41Fb;
    IBEP20 public constant ATX = IBEP20(atx);
    address public constant CEO = 0xe6497e1F2C5418978D5fC2cD32AA23315E7a41Fb;


    uint256 private constant veryBigNumber = 10 ** 36;
    address[] public poolMembers;
    mapping (address => uint256) public tokensInWallet;
    mapping (address => bool) public sold;

    event BnbRescued();

    modifier onlyCEO(){
        require (msg.sender == CEO, "Only the CEO can do that");
        _;
    }

	constructor() {}

    function initializePoolMembers() external onlyCEO {
        uint256 poolMembersTotal = poolMembers.length;
        for(uint i = 0; i<poolMembersTotal;i++){
            address wallet = poolMembers[i];
            uint256 tokenAmount = ATX.balanceOf(wallet);
            tokensInWallet[wallet] = tokenAmount;
        }
    }

    function depositBNB() external payable {
        uint256 poolMembersTotal = poolMembers.length;
        uint256 totalTokensInPool = 0;

        for(uint i = 0; i<poolMembersTotal;i++){
            address wallet = poolMembers[i];
            uint256 tokenAmount = ATX.balanceOf(wallet);
            if(tokensInWallet[wallet] > tokenAmount || sold[wallet]) {
                sold[poolMembers[i]] = true;
                continue;
            }
            totalTokensInPool += tokenAmount;
        }

        uint256 rewardsPerToken = msg.value * veryBigNumber / totalTokensInPool;

        for(uint i = 0; i<poolMembersTotal;i++){
            address to = poolMembers[i];
            if(sold[to]) continue;
            uint256 rewardsAmount = tokensInWallet[to] * rewardsPerToken / veryBigNumber;
            payable(to).transfer(rewardsAmount);
        }
    }

    function addPoolWallets(address[] memory wallets) external onlyCEO {
        uint256 totalWallets = wallets.length;
        for(uint i = 0; i<totalWallets;i++) poolMembers.push(wallets[i]);
    }


    function rescueBnb() external onlyCEO {
        if(address(this).balance > 0) {
            (bool success,) = address(CEO).call{value: address(this).balance}("");
            if(success) emit BnbRescued();
        }
    }
}