// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Import point system.
import "./interfaces/IPoints.sol";

contract Boombox {
    // Tiers available for artist signing.
    enum Tier {
        None,
        Bronze,
        Silver,
        Gold,
        Platinum,
        Diamond
    }

    // Array of participants in the pool.
    mapping(string => address[]) public participants;
    // Mapping the participant to the tier they signed up for.
    mapping(string => mapping(address => Tier)) public participantTier;

    // Indexes for easier lookups.
    mapping(string => mapping(uint => address)) public participantsByIndex;
    mapping(string => mapping(address => uint)) public participantIndex;
    mapping(string => mapping(address => uint)) public pointsAwardedByArtist;

    // Tiers
    mapping(string => mapping(Tier => uint)) public tierCosts;
    mapping(string => mapping(Tier => uint)) public tierPercentages;
    uint[] public defaultTierCosts = [
        0,
        20000000,
        60000000,
        140000000,
        300000000,
        620000000
    ];

    uint[] public defaultTierPercentages = [70, 5, 5, 5, 5, 10];

    // TODO: Change this so that it just goes to a single wallet and claims for an artist are subtracted from what htey owe
    // TODO: Also likely need a mapping for how much a spotify id is owed - artistPointsBank below
    // The percentage of the rewards that the taker receives.
    uint public artistPercentage;
    uint public treasuryPercentage;
    address public treasury;
    // The core Points contract, for adding and subtracting points.
    IPoints public points;
    uint256 public pointSystemId;

    // These are the total points assigned to the pool.
    mapping(string => uint) public totalPoints;
    // These get reset to 0 whenever there is a distribution event.
    mapping(string => uint) public pointsToDistribute;
    mapping(string => uint) public artistPointsBank;

    address public owner;

    modifier onlyAdmin() {
        require(
            points.getRole(pointSystemId, msg.sender) == Role.Admin,
            "Only admin"
        );
        _;
    }

    modifier onlyOwnerOrAdmin() {
        require(msg.sender == owner || points.getRole(pointSystemId, msg.sender) == Role.Admin, "Only owner or admin");
        _;
    }

    constructor() {
        // Initial points contract.
        points = IPoints(0x000000000c2B4A5816cbb76e9bb3f70D175940A3);
        owner = msg.sender; // Specifically to Boombox.
    }

    function initialize(
        uint256 _artistPercentage,
        uint256 _treasuryPercentage,
        address _treasury
    ) external onlyAdmin {
        require(
            _artistPercentage <= 100,
            "Taker percentage must be less than or equal to 100"
        );

        artistPercentage = _artistPercentage;
        treasuryPercentage = _treasuryPercentage;
        treasury = _treasury;
    }

    function setOwner(address _owner) external onlyOwnerOrAdmin {
        owner = _owner;
    }

    function setPointsContract(address _pointsAddress) external onlyOwnerOrAdmin {
        points = IPoints(_pointsAddress);
    }

    function setPointSystemId(uint256 _pointSystemId) external {
        // Can be initialized or changed by an admin.
        require(pointSystemId == 0 || points.getRole(pointSystemId, msg.sender) == Role.Admin, "Only admin");
        pointSystemId = _pointSystemId;
    }

    // setting points to 0 withdraws everything
    function withdrawToArtist(
        string memory _artistId,
        address _artistAddress,
        uint points_
    ) external onlyAdmin {
        uint artistPoints = artistPointsBank[_artistId];
        uint withdrawPoints = artistPoints;
        if (points_ < artistPoints) {
            withdrawPoints = points_;
        }

        points.addPoints(pointSystemId, _artistAddress, withdrawPoints);
        artistPointsBank[_artistId] = artistPoints - withdrawPoints;
    }

    function setTreasury(address _treasury) external onlyAdmin {
        treasury = _treasury;
    }

    function setArtistPercentage(uint _percentage) external onlyAdmin {
        artistPercentage = _percentage;
    }

    function setTreasuryPercentage(uint _percentage) external onlyAdmin {
        treasuryPercentage = _percentage;
    }

    function setTierCost(
        string memory _artistId,
        Tier _tier,
        uint _cost
    ) external onlyAdmin {
        tierCosts[_artistId][_tier] = _cost;
    }

    function setDefaultTierCost(uint[] memory defaults) external onlyAdmin {
        for (uint i = 0; i <= uint(Tier.Diamond); i++) {
            defaultTierCosts[i] = defaults[i];
        }
    }

    function setDefaultTierPercentages(uint[] memory defaults) external onlyAdmin {
        for (uint i = 0; i <= uint(Tier.Diamond); i++) {
            defaultTierPercentages[i] = defaults[i];
        }
    }

    function setBatchTierCost(
        string memory _artistId,
        uint[] memory _cost
    ) external onlyAdmin {
        for (uint i = 0; i <= uint(Tier.Diamond); i++) {
            tierCosts[_artistId][Tier(i)] = _cost[i];
        }
    }

    function setTierPercentage(
        string memory _artistId,
        Tier _tier,
        uint _percentage
    ) public onlyAdmin {
        tierPercentages[_artistId][_tier] = _percentage;
    }

    function getParticipants(
        string memory artistId
    ) external view returns (address[] memory) {
        return participants[artistId];
    }

    function resetArtist(string memory artistId) external onlyAdmin {
        for (uint i = 0; i < participants[artistId].length; i++) {
            address participant = participants[artistId][i];
            delete participantIndex[artistId][participant];
            delete participantsByIndex[artistId][i];
            delete participantTier[artistId][participant];
        }

        delete participants[artistId];

        // Reset total points, points to distribute, and artist points bank
        totalPoints[artistId] = 0;
        pointsToDistribute[artistId] = 0;
        artistPointsBank[artistId] = 0;
    }

    function getTierCostForUser(
        string memory _artistId,
        Tier _tier,
        address _user
    ) external view returns (uint) {
        return
            tierCosts[_artistId][_tier] -
            tierCosts[_artistId][participantTier[_artistId][_user]];
    }

    function signArtist(
        string memory artistId,
        address user,
        uint _points
    ) external onlyAdmin {
        uint pointsForArtist = 0;

        // Subtract the points from the user.
        points.subtractPoints(pointSystemId, user, _points);
        totalPoints[artistId] += _points;
        pointsForArtist += (_points * artistPercentage) / 100;
        artistPointsBank[artistId] += pointsForArtist;
        pointsToDistribute[artistId] += _points - pointsForArtist;

        // Check if the user is already a participant.
        if (participantIndex[artistId][user] == 0) {
            // Add the user to the participants array.
            participants[artistId].push(user);
            // Set the participant index.
            participantIndex[artistId][user] = participants[artistId].length;
            // Set the participant by index.
            participantsByIndex[artistId][participants[artistId].length] = user;
            participantTier[artistId][user] = Tier.None;
        }
    }

    function upgradeUserTier(
        string memory artistId,
        address user,
        Tier tier
    ) external onlyAdmin {
        require(
            participantTier[artistId][user] < tier,
            "Can only upgrade tier"
        );
        require(tier != Tier.None, "Can not downgrade");

        if (tierCosts[artistId][tier] == 0) {
            for (uint i = 0; i <= uint(Tier.Diamond); i++) {
                tierCosts[artistId][Tier(i)] = defaultTierCosts[i];
            }
        }
        uint _points = tierCosts[artistId][tier] -
            tierCosts[artistId][participantTier[artistId][user]];
        // Subtract the points from the user.
        points.subtractPoints(pointSystemId, user, _points);

        totalPoints[artistId] += _points;
        uint256 pointsForTreasury = (_points * treasuryPercentage) / 100;
        points.addPoints(pointSystemId, treasury, pointsForTreasury);
        artistPointsBank[artistId] += _points - pointsForTreasury;
        participantTier[artistId][user] = tier;
    }

    function distribute(string memory artistId) external {
        // Check that the reward is not zero.
        require(pointsToDistribute[artistId] != 0, "Reward is zero");

        uint unawardedPoints = pointsToDistribute[artistId];

        // Ensure tier percentages are initialized
        if (tierPercentages[artistId][Tier.None] == 0) {
            for (uint i = 0; i <= uint(Tier.Diamond); i++) {
                setTierPercentage(artistId, Tier(i), defaultTierPercentages[i]);
            }
        }

        // Calculate participantsTierCount
        // Mapping that says how many people are in each tier
        uint[6] memory participantsTierCount;
        for (uint i = 0; i < participants[artistId].length; i++) {
            address participant = participants[artistId][i];
            if (participantTier[artistId][participant] >= Tier.None) {
                participantsTierCount[0]++;
            }
            if (participantTier[artistId][participant] >= Tier.Bronze) {
                participantsTierCount[1]++;
            }
            if (participantTier[artistId][participant] >= Tier.Silver) {
                participantsTierCount[2]++;
            }
            if (participantTier[artistId][participant] >= Tier.Gold) {
                participantsTierCount[3]++;
            }
            if (participantTier[artistId][participant] >= Tier.Platinum) {
                participantsTierCount[4]++;
            }
            if (participantTier[artistId][participant] == Tier.Diamond) {
                participantsTierCount[5]++;
            }
        }

        // Calculate total percentage for participants in all tiers
        uint totalPercentage = 0;
        for (uint i = 0; i <= uint(Tier.Diamond); i++) {
            totalPercentage += tierPercentages[artistId][Tier(i)];
        }

        // Start distributing from the highest tier
        for (uint t = uint(Tier.Diamond) + 1; t > 0; t--) {
            uint i = t - 1;
            uint tierPercentage = tierPercentages[artistId][Tier(i)];
            uint participantsInTier = participantsTierCount[uint(Tier(i))];

            // If there are no participants in this tier, continue to the next tier
            if (tierPercentage == 0 || participantsInTier == 0) {
                continue;
            }

            // Calculate points to distribute for this tier
            uint pointsForTier = (pointsToDistribute[artistId] * tierPercentage) /
                totalPercentage;

            if (i == 0) pointsForTier = unawardedPoints;

            // Distribute points to participants in this tier
            for (uint j = 0; j < participants[artistId].length; j++) {
                address participant = participants[artistId][j];
                if (participantTier[artistId][participant] >= Tier(i)) {
                    uint pointsPerParticipant = pointsForTier / participantsInTier;
                    pointsAwardedByArtist[artistId][
                        participant
                    ] += pointsPerParticipant;
                    points.addPoints(pointSystemId, participant, pointsPerParticipant);
                }
            }

            // Update pointsToDistribute and totalPercentage for next iteration
            unawardedPoints -= pointsForTier;
        }

        // Reset the points to distribute.
        pointsToDistribute[artistId] = 0;
    }
}
