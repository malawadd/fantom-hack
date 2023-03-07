//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Hawd} from "./Hawd.sol";

/// @notice Only the ERC-20 functions we need
interface IERC20 {
    /// @notice Get the balance of aUSDC in No Pool No Game
    /// @notice and balance of USDC from the Player
    function balanceOf(address acount) external view returns (uint256);

    /// @notice Approve the deposit of USDC from No Pool No Game to Aave
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Confirm the allowed amount before deposit
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    /// @notice Withdraw USDC from No Pool No Game
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    /// @notice Transfer USDC from User to No Pool No Game
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /// @notice Mint NPNGaUSDC when user deposits on the pool
    function mint(address sender, uint256 amount) external;

    /// @notice Burn NPNGaUSDC when user withdraws from the pool
    function burn(address sender, uint256 amount) external;
}

/// @notice Only the PoolAave functions we need
interface PoolAave {
    /// @notice Deposit USDC to Aave Pool
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /// @notice Withdraw USDC from Aave Pool
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external;
}

/// BEGINNING OF THE CONTRACT
contract HawdPool is Hawd {
    struct EndContest {
        uint256 poolValue;
        uint256 prizePool;
        uint256 rewards;
    }

    /// @notice balance of Users in the Pool
    mapping(address => uint256) private balanceOfUser;

    /// @notice Sum of all deposits during the current contest
    uint256 private currentContestDeposits;

    /// @notice Sum of all witdhraws during the current contest
    uint256 private currentContestWithdraws;

    /// @notice Record the last Contest of Deposit
    mapping(address => uint256) private lastIdContestOfDeposit;

    /// @notice Pool Value and Rewards at the end of each contest
    mapping(uint256 => EndContest) private endContest;

    mapping(uint256 => uint256) private remainedUnclaimedRewardsPerContest;

    /// @notice balance of total claimed rewards per player
    mapping(address => uint256) private balanceOfClaimedRewards;

    IERC20 private usdcToken;
    IERC20 private aUsdcToken;
    IERC20 private hawdToken;
    PoolAave private poolAave;

    constructor() {
        usdcToken = IERC20(0x382E773695e6877B0BDc9d02DFe1594061879fE5);
        poolAave = PoolAave(0x95b1B6470eAF8cC4A03d2D44C6b54eBB8ede8C30);
        aUsdcToken = IERC20(0x8dAC4Da226Cc4569d47d0fB32bb4dF1CB21dbEA4);
        hawdToken = IERC20(0x626A569a8Dc1842eBd60f8D09701973222551Fa0);

        endContest[0].poolValue = 0;
        endContest[0].prizePool = 0;
        endContest[0].rewards = 0;
    }

    /// WRITE FUNCTIONS

    /// @notice Update the NPNG Token address if a new contract is deployed
    function changehawdTokenAddress(address _newAddress) public onlyOwner {
        hawdToken = IERC20(_newAddress);
    }

    /// @notice Deposit USDC on Pool which will be deposited on Aave and get the same amount ofNPNGaUSCD
    function depositOnAave(uint256 _amount) public {
        require(
            _amount <= usdcToken.balanceOf(msg.sender),
            "Insufficent amount of USDC"
        );
        require(
            _amount <= usdcToken.allowance(msg.sender, address(this)),
            "Insufficient allowed USDC"
        );
        usdcToken.transferFrom(msg.sender, address(this), _amount);
        usdcToken.approve(address(poolAave), _amount);
        poolAave.supply(address(usdcToken), _amount, address(this), 0);
        balanceOfUser[msg.sender] += _amount;
        currentContestDeposits += _amount;
        hawdToken.mint(msg.sender, _amount);
        lastIdContestOfDeposit[msg.sender] = Hawd.currentIdContest;
    }

    /// @notice Withdraw from the Pool, it will be withdraw from Aave and NPNG Token will be burnt
    function withdraw(uint256 _amount) public {
        require(balanceOfUser[msg.sender] >= _amount, "Insufficient balance");
        require(
            lastIdContestOfDeposit[msg.sender] + 2 <= Hawd.currentIdContest,
            "Please wait 2 contests after your deposit to witdraw"
        );
        poolAave.withdraw(address(usdcToken), _amount, address(this));
        usdcToken.transfer(msg.sender, _amount);
        balanceOfUser[msg.sender] -= _amount;
        currentContestWithdraws += _amount;
        hawdToken.burn(msg.sender, _amount);
    }

    /// @notice update the Id of the contest based on the block.timestamp and the game frequence
    /// @notice save info about Pool states from the previous id Contest
    function updateContest() public {
        require(
            msg.sender == recorderAddress,
            "You are not allowed to update contest!"
        );
        require(
            block.timestamp >= Hawd.lastContestTimestamp + Hawd.gameFrequence,
            "No contest update!"
        );
        lastContestTimestamp = block.timestamp;
        uint256 contestPoolValue = endContest[currentIdContest - 1].poolValue +
            currentContestDeposits -
            currentContestWithdraws +
            endContest[currentIdContest - 1].rewards;
        uint256 aavePoolValue = aUsdcToken.balanceOf(address(this));
        uint256 contestPrizePool = aavePoolValue - contestPoolValue;
        uint256 rewardsPerContest = getRewardsPerContest(
            currentIdContest,
            contestPrizePool
        );
        endContest[currentIdContest].poolValue = contestPoolValue;
        endContest[currentIdContest].prizePool = contestPrizePool;
        endContest[currentIdContest].rewards = rewardsPerContest;

        remainedUnclaimedRewardsPerContest[
            currentIdContest
        ] = rewardsPerContest;
        currentContestDeposits = 0;
        currentContestWithdraws = 0;
        currentIdContest++;
    }

    /// @notice Record the contest played by the player to verify if he can and save his request
    function getPlay() public {
        require(balanceOfUser[msg.sender] > 0, "No deposit, No Game!");
        Hawd.requestPlaying();
    }

    /// @notice Save the score after the play
    function saveScore(address _player, uint256 _score) public {
        require(
            msg.sender == recorderAddress,
            "You are not allowed to save a score!"
        );
        require(
            contestPlayerStatus[_player][currentIdContest].requested == true,
            "No request from player"
        );
        require(
            contestPlayerStatus[_player][currentIdContest].played == false,
            "Player already played"
        );
        Hawd.contestsResult[currentIdContest].push(
            ContestsResult(_player, _score, balanceOfUser[_player])
        );
        contestPlayerStatus[_player][currentIdContest].played = true;
        numberOfPlayersPerContest[currentIdContest]++;
    }

    /// @notice claim the pending rewards
    function claim() public {
        uint256 onClaiming = 0;
        uint256 reward;
        for (uint256 i = currentIdContest - 1; i > 0; i--) {
            if (contestPlayerStatus[msg.sender][i].claimed == true) {
                break;
            } else {
                reward = getRewardPerPlayerPerContest(msg.sender, i);
                onClaiming += reward;
                remainedUnclaimedRewardsPerContest[i] -= reward;
                contestPlayerStatus[msg.sender][i].claimed = true;
            }
        }
        if (onClaiming > 0) {
            balanceOfUser[msg.sender] += onClaiming;
            balanceOfClaimedRewards[msg.sender] += onClaiming;
            hawdToken.mint(msg.sender, onClaiming);
        }
    }

    /// READ FUNCTIONS
    function getUserBalance(address _account) public view returns (uint256) {
        return (balanceOfUser[_account]);
    }

    ///@notice Get all the rewards claimed from a player
    function getTotalClaimedRewards(address _account)
        public
        view
        returns (uint256)
    {
        return (balanceOfClaimedRewards[_account]);
    }

    /// @notice get addresses, scores and deposits of top 10 players for a contest
    function getWinnersInfo(uint256 _idContest)
        public
        view
        returns (ContestsResult[11] memory)
    {
        uint256 playerScore;
        uint256 winnersDeposit = 0;
        ContestsResult[11] memory winnersRank;

        for (uint256 i = 0; i < contestsResult[_idContest].length; i++) {
            playerScore = contestsResult[_idContest][i].score;
            uint256 rank = 1;
            for (uint256 j = 0; j < contestsResult[_idContest].length; j++) {
                if (playerScore > contestsResult[_idContest][j].score) {
                    rank++;
                }
            }
            if (rank < 11) {
                winnersDeposit += contestsResult[_idContest][i].balancePlayer;
                winnersRank[rank].player = contestsResult[_idContest][i].player;
                winnersRank[rank].score = contestsResult[_idContest][i].score;
                winnersRank[rank].balancePlayer = contestsResult[_idContest][i]
                    .balancePlayer;
            }
        }
        winnersRank[0].balancePlayer = winnersDeposit;
        return (winnersRank);
    }

    /// @notice for each contest, get the cumimlated rewards of the top 10 players
    function getRewardsPerContest(uint256 _idContest, uint256 _globalPrizePool)
        public
        view
        returns (uint256)
    {
        ContestsResult[11] memory winnersRank = getWinnersInfo(_idContest);
        uint256 winnersDeposit = winnersRank[0].balancePlayer;
        uint256 totalRewards;
        for (uint256 i = 1; i < 11; i++) {
            totalRewards +=
                (((_globalPrizePool * winnersRank[i].balancePlayer * 10**6) /
                    winnersDeposit) * (101 - i)**5) /
                10**16;
        }
        return (totalRewards);
    }

    /// @notice for each player, get his rewards for a specific contest
    function getRewardPerPlayerPerContest(address _player, uint256 _idContest)
        public
        view
        returns (uint256)
    {
        ContestsResult[11] memory winnersRank = getWinnersInfo(_idContest);
        uint256 winnersDeposit = winnersRank[0].balancePlayer;
        uint256 reward = 0;
        for (uint256 i = 1; i < 11; i++) {
            if (_player == winnersRank[i].player) {
                reward =
                    (((endContest[_idContest].prizePool *
                        winnersRank[i].balancePlayer *
                        10**6) / winnersDeposit) * (101 - i)**5) /
                    10**16;
                break;
            }
        }
        return (reward);
    }

    /// @notice table of last 10 contests for a player, used for ranking history in the Page Account
    function getAccountTable(address _player)
        public
        view
        returns (AccountTable[10] memory)
    {
        AccountTable[10] memory accountTable;
        uint256 indexDecrement;
        uint256 j = 0;
        uint256 lastClosedIdContest = currentIdContest - 1;
        uint256 contestRank;
        if (lastClosedIdContest < 10) {
            indexDecrement = lastClosedIdContest;
        } else {
            indexDecrement = 10;
        }
        for (
            uint256 i = lastClosedIdContest;
            i > lastClosedIdContest - indexDecrement;
            i--
        ) {
            contestRank = getContestRank(i, _player);
            if (contestRank > 0 && contestRank < 11) {
                accountTable[j] = AccountTable({
                    idContest: i,
                    rank: contestRank,
                    participant: numberOfPlayersPerContest[i],
                    prize: getRewardPerPlayerPerContest(_player, i)
                });
            } else {
                accountTable[j] = AccountTable({
                    idContest: i,
                    rank: contestRank,
                    participant: numberOfPlayersPerContest[i],
                    prize: 0
                });
            }
            j++;
        }
        return (accountTable);
    }

    /// @notice table of top 10 players for a contest, used for modal contest in the Page Account
    function getContestTable(uint256 _idContest)
        public
        view
        returns (ContestTable[10] memory)
    {
        ContestTable[10] memory contestTable;
        ContestsResult[11] memory winnersRank = getWinnersInfo(_idContest);
        uint256 winnersDeposit = winnersRank[0].balancePlayer;
        for (uint256 i = 0; i < 10; i++) {
            uint256 j = i + 1;
            contestTable[i].rank = j;
            contestTable[i].score = winnersRank[j].score;
            contestTable[i].player = winnersRank[j].player;
            contestTable[i].prize =
                (((endContest[_idContest].prizePool *
                    winnersRank[j].balancePlayer *
                    10**6) / winnersDeposit) * (101 - j)**5) /
                10**16;
        }
        return (contestTable);
    }

    /// @notice get the Prize Pool of the cinnrent contest
    function getGlobalPrizePool() public view returns (uint256) {
        uint256 contestPoolValue = endContest[currentIdContest - 1].poolValue +
            currentContestDeposits -
            currentContestWithdraws +
            endContest[currentIdContest - 1].rewards;
        uint256 aavePoolValue = aUsdcToken.balanceOf(address(this));
        return (aavePoolValue - contestPoolValue);
    }

    /// @notice Get the pending rewards of a player. These rewards can be claimed
    function getPendingRewards(address _account) public view returns (uint256) {
        uint256 onClaiming = 0;
        for (uint256 i = currentIdContest - 1; i > 0; i--) {
            if (contestPlayerStatus[_account][i].claimed == true) {
                break;
            } else {
                onClaiming += getRewardPerPlayerPerContest(_account, i);
            }
        }
        return (onClaiming);
    }
}
