
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//  /$$                 /$$ /$$                 /$$$$$$$                     
// | $$                |__/| $$                | $$__  $$                    
// | $$        /$$$$$$  /$$| $$   /$$  /$$$$$$ | $$  \ $$  /$$$$$$   /$$$$$$ 
// | $$       |____  $$| $$| $$  /$$/ |____  $$| $$  | $$ /$$__  $$ /$$__  $$
// | $$        /$$$$$$$| $$| $$$$$$/   /$$$$$$$| $$  | $$| $$  \ $$| $$  \ $$
// | $$       /$$__  $$| $$| $$_  $$  /$$__  $$| $$  | $$| $$  | $$| $$  | $$
// | $$$$$$$$|  $$$$$$$| $$| $$ \  $$|  $$$$$$$| $$$$$$$/|  $$$$$$/|  $$$$$$$
// |________/ \_______/|__/|__/  \__/ \_______/|_______/  \______/  \____  $$
//                                                                  /$$  \ $$
//                                                                 |  $$$$$$/
//                                                                  \______/ 
//   /$$$$$$                                                                 
//  /$$__  $$                                                                
// | $$  \__/  /$$$$$$   /$$$$$$   /$$$$$$$  /$$$$$$                         
// |  $$$$$$  /$$__  $$ |____  $$ /$$_____/ /$$__  $$                        
//  \____  $$| $$  \ $$  /$$$$$$$| $$      | $$$$$$$$                        
//  /$$  \ $$| $$  | $$ /$$__  $$| $$      | $$_____/                        
// |  $$$$$$/| $$$$$$$/|  $$$$$$$|  $$$$$$$|  $$$$$$$                        
//  \______/ | $$____/  \_______/ \_______/ \_______/                        
//           | $$                                                            
//           | $$                                                            
//           |__/  


import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './interfaces/IBEP20.sol';
import './IDividendDistributor.sol';

contract DividendDistributor is IDividendDistributor, Ownable {
    using SafeMath for uint256;

    address _token;
    address public manager;

    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
    }

    IBEP20 reflectionToken;

    address[] shareholders;
    mapping (address => uint256) shareholderIndexes;
    mapping (address => uint256) shareholderClaims;

    mapping (address => Share) public shares;

    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public totalDistributed;
    uint256 public dividendsPerShare;

    uint256 public dividendsPerShareAccuracyFactor = 10 ** 36;

    uint256 public minPeriod = 1 hours;
    uint256 public minDistribution = 1 * (10 ** 18);

    uint256 currentIndex;

    modifier onlyToken() {
        require(msg.sender == _token); _;
    }

    constructor (address _sourceToken, address _reflectionToken) {
        reflectionToken = IBEP20(_reflectionToken);
        _token = _sourceToken;
    }

    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external override onlyToken {
        minPeriod = _minPeriod;
        minDistribution = _minDistribution;
    }

    function setShare(address shareholder, uint256 amount) external override onlyToken {
        if(shares[shareholder].amount > 0){
            distributeDividend(shareholder);
        }
    
        if(amount > 0 && shares[shareholder].amount == 0){
            addShareholder(shareholder);
        }else if(amount == 0 && shares[shareholder].amount > 0){
            removeShareholder(shareholder);
        }

        totalShares = totalShares.sub(shares[shareholder].amount).add(amount);
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
    }

    function deposit(uint amount) external override onlyToken {
        totalDividends = totalDividends.add(amount);
        dividendsPerShare = dividendsPerShare.add(dividendsPerShareAccuracyFactor.mul(amount).div(totalShares));
    }

    function process(uint256 gas) external override onlyToken {
        uint256 shareholderCount = shareholders.length;

        if(shareholderCount == 0) { return; }

        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();

        uint256 iterations = 0;

        while(gasUsed < gas && iterations < shareholderCount) {
            if(currentIndex >= shareholderCount){
                currentIndex = 0;
            }

            if(shouldDistribute(shareholders[currentIndex])){
                distributeDividend(shareholders[currentIndex]);
            }

            gasUsed = gasUsed.add(gasLeft.sub(gasleft()));
            gasLeft = gasleft();
            currentIndex++;
            iterations++;
        }
    }

    function shareholderCount() external view returns(uint){
        return shareholders.length;
    }

    function setReflectionToken(address _relectionToken) external onlyOwner{
        reflectionToken = IBEP20(_relectionToken);
        totalDividends = 0;
        totalDistributed = 0;
        dividendsPerShare = 0;
    }

    function distributeDividendRange(uint _from, uint _to) external onlyOwner {
        for(uint index = _from; index < _to; index++){
            if(shouldDistribute(shareholders[index])){
                distributeDividend(shareholders[index]);
            }
        }
    }

    function resetDistributeDividend(uint _from, uint _to) external onlyOwner{
        for(uint index = _from; index < _to; index++){
            if(shouldDistribute(shareholders[index])){
                distributeDividend(shareholders[index]);
            }
            address shareholder = shareholders[index];
            shares[shareholder].totalRealised = 0;
            shares[shareholder].totalExcluded = 0;
        }
    }

    function shouldDistribute(address shareholder) internal view returns (bool) {
        return shareholderClaims[shareholder] + minPeriod < block.timestamp
        && getUnpaidEarnings(shareholder) > minDistribution;
    }

    function distributeDividend(address shareholder) internal {
        if(shares[shareholder].amount == 0){ return; }

        uint256 amount = getUnpaidEarnings(shareholder);
        if(amount > 0){
            totalDistributed = totalDistributed.add(amount);
            reflectionToken.transfer(shareholder, amount);
            shareholderClaims[shareholder] = block.timestamp;
            shares[shareholder].totalRealised = shares[shareholder].totalRealised.add(amount);
            shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
        }
    }

    function claimDividend() external {
        distributeDividend(msg.sender);
    }

    function getUnpaidEarnings(address shareholder) public view returns (uint256) {
        if(shares[shareholder].amount == 0){ return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if(shareholderTotalDividends <= shareholderTotalExcluded){ return 0; }

        return shareholderTotalDividends.sub(shareholderTotalExcluded);
    }

    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return share.mul(dividendsPerShare).div(dividendsPerShareAccuracyFactor);
    }

    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);
    }

    function removeShareholder(address shareholder) internal {
        shareholders[shareholderIndexes[shareholder]] = shareholders[shareholders.length-1];
        shareholderIndexes[shareholders[shareholders.length-1]] = shareholderIndexes[shareholder];
        shareholders.pop();
    }

    function withdrawBNB(address to, uint amount) external onlyOwner{
        payable(to).call{value: amount}("");
    }
}