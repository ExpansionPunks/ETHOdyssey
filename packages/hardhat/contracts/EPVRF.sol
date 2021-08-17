// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "./UniformRandomNumber.sol";
import "hardhat/console.sol";

contract ExpansionPunks is
    ERC721,
    ERC721Enumerable,
    Ownable,
    ReentrancyGuard,
    VRFConsumerBase
{
    using SafeMath for uint256;

    // ----- Token config -----
    // Total number of ExpansionPunks that can be minted
    uint16 public constant maxSupply = 100;
    // Number of ExpansionPunks reserved for promotion & giveaways
    uint8 public totalReserved = 11;
    // IPFS hash of the 100x100 grid of the ExpansionPunks
    string public EP_PROVENANCE_SHA256 = "-";
    string public EP_PROVENANCE_IPFS = "-";
    // Root of the IPFS metadata store
    string public baseURI = "";
    // Current number of tokens
    uint16 public numTokens = 0;
    // remaining ExpansionPunks in the reserve
    uint8 private _reserved;

    // ----- Sale config -----
    // Price for a single token
    uint256 private _price = 0.06 ether;
    // Can you mint tokens already
    bool private _saleStarted;
    // Additional random offset
    uint256 public startingIndex;

    // ----- Owner config -----
    address jp = 0xE6cC8D91483DfC341622Ea6fA6eaEf2DecD7bBEA;
    address fu = 0x6EC25460f85F23181f5694c7c61C74027fCDdB03;
    address dao = 0xAAAA2870050f30510e14FBf38922927C334B4cC0;

    // Mapping which token we already handed out
    uint16[maxSupply] private indices;

    bytes32 internal keyHash;
    uint256 internal fee;

    // SWAP
    IUniswapV2Router02 public uniswapRouter;
    address LinkToken = 0x01BE23585060835E02B77ef475b0Cc51aA1e0709;

    // Constructor. We set the symbol and name and start with sa
    constructor()
        // address vrf_coord,
        // address link_token,
        VRFConsumerBase(
            0xb3dCcb4Cf7a26f6cf6B120Cf5A73875B7BBc655B,
            0x01BE23585060835E02B77ef475b0Cc51aA1e0709
        )
        ERC721("PIZZACAKE", "PIZZA")
    {
        // jp = jpIn;
        // fu = fuIn;
        // dao = daoIn;
        _saleStarted = false;
        _reserved = totalReserved;
        keyHash = 0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311;
        fee = 0.1 * 10**18; // 0.1 LINK (Varies by network)

        uniswapRouter = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );
        //require(uniswapRouter.approve(address(uniswapRouter), 1000000000000), 'approve failed.');
    }

    receive() external payable {}

    // restrict to onyl allow when we have a running sale
    modifier saleIsOpen() {
        require(_saleStarted == true, "Sale not started yet");
        _;
    }


    // restrict to onyl allow when we have a running sale
    modifier onlyAdmin() {
        require(
            _msgSender() == owner() || _msgSender() == jp || _msgSender() == fu,
            "Ownable: caller is not the owner"
        );
        _;
    }

    // ----- ERC721 functions -----
    function _baseURI() internal view override(ERC721) returns (string memory) {
        return baseURI;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ----- Getter functions -----
    function getPrice() public view returns (uint256) {
        return _price;
    }

    // function getReservedLeft() public view returns (uint256) {
    //     return _reserved;
    // }

    function getSaleStarted() public view returns (bool) {
        return _saleStarted;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    // ----- Setter functions -----
    // These functions allow us to change values after contract deployment

    function setBaseURI(string memory _URI) external onlyOwner {
        baseURI = _URI;
    }

    // ----- Minting functions -----

    struct MintRequest {
        address receiver;
        uint8 count;
    }

    mapping(bytes32 => MintRequest) public randomRequests;

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        uint16 totalSize = maxSupply - numTokens;
        uint16 _randomNumber = UniformRandomNumber.uniform(
            uint16(randomness),
            totalSize
        );
        
        MintRequest memory request = randomRequests[requestId];
        for (uint8 i; i < request.count; i++) {
            uint16 tokenID = randomToIndex(_randomNumber + i);
            numTokens = numTokens + 1;
            _safeMint(request.receiver, tokenID);
        }
    }

    function randomToIndex(uint16 index) public returns (uint16) {
        uint16 value = 0;
        uint16 totalSize = maxSupply - numTokens;
        if (indices[index] != 0) {
            value = indices[index];
        } else {
            value = index;
        }

        // Move last value to selected position
        if (indices[totalSize - 1] == 0) {
            // Array position not initialized, so use position
            indices[index] = totalSize - 1;
        } else {
            // Array position holds a value so use that
            indices[index] = indices[totalSize - 1];
        }

        // We start our tokens at 10000
        return value + (10000);
    }

    function mint(uint8 _number, uint256 _deadline)
        external
        payable
        nonReentrant
        saleIsOpen
    {
        uint16 supply = uint16(totalSupply());
        require(
            supply + _number <= maxSupply - _reserved,
            "Not enough ExpansionPunks left."
        );
        require(
            _number < 21,
            "You cannot mint more than 20 ExpansionPunks at once!"
        );
        require(_number * _price == msg.value, "Inconsistent amount sent!");

        // How many fully batches are we generating
        uint8 rounds = _number / 3;
        // are there any remainders after our batches
        uint8 remainder = _number - (rounds * 3);

        uint256 amountOut = fee * rounds;
        if (remainder > 0) {
            amountOut = amountOut + fee;
        }

        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = LinkToken;

        uniswapRouter.swapETHForExactTokens{value: msg.value}(
            amountOut,
            path,
            address(this),
            _deadline
        );

        for (uint8 i = 0; i < rounds; i++) {
            bytes32 requestId = getRandomNumber();
            MintRequest storage request = randomRequests[requestId];
            request.receiver = msg.sender;
            request.count = 3;
        }
        if (remainder > 0) {
            bytes32 requestId = getRandomNumber();
            MintRequest storage request = randomRequests[requestId];
            request.receiver = msg.sender;
            request.count = remainder;
        }
    }

    function getRandomNumber() public returns (bytes32 requestId) {
        require(
            LINK.balanceOf(address(this)) >= fee,
            "Not enough LINK - fill contract with faucet"
        );
        return requestRandomness(keyHash, fee);
    }

    // ----- Sale functions -----
    function setStartingIndex() public onlyAdmin {
        require(startingIndex == 0, "Starting index is already set");

        // BlockHash only works for the most 256 recent blocks.
        uint256 _block_shift = uint256(
            keccak256(abi.encodePacked(block.difficulty, block.timestamp))
        );
        _block_shift = 1 + (_block_shift % 255);

        // This shouldn't happen, but just in case the blockchain gets a reboot?
        if (block.number < _block_shift) {
            _block_shift = 1;
        }

        uint256 _block_ref = block.number - _block_shift;
        startingIndex = uint256(blockhash(_block_ref)) % maxSupply;

        // Prevent default sequence
        if (startingIndex == 0) {
            startingIndex = startingIndex + 1;
        }
    }

    function flipSaleStarted() external onlyAdmin {
        _saleStarted = !_saleStarted;

        if (_saleStarted && startingIndex == 0) {
            setStartingIndex();
        }
    }

    // ----- Helper functions -----
    // Helper to list all the ExpansionPunks of a wallet
    function walletOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(_owner);

        uint256[] memory tokensId = new uint256[](tokenCount);
        for (uint256 i; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokensId;
    }

    function claimReserved(uint8 _number, address _receiver)
        external
        onlyAdmin
    {
        require(_number <= _reserved, "That would exceed the max reserved.");
        bytes32 requestId = getRandomNumber();
        MintRequest storage request = randomRequests[requestId];
        request.receiver = _receiver;
        request.count = _number;
        _reserved = _reserved - _number;
    }

    // This will take the eth on the contract and split it based on the logif below and send it our
    // Split logic:
    // We funnel 1/3 for each dev and 1/3 into the ExpansionPunkDAO
    function withdraw() public onlyAdmin {
        uint256 _balance = address(this).balance;
        uint256 _split = _balance.mul(33).div(100);

        require(payable(jp).send(_split));
        require(payable(fu).send(_split));
        require(payable(dao).send(_balance.sub(_split * 2)));
    }
}
