// SPDX-License-Identifier: MIT
pragma solidity =0.8.30;

contract Filmrare {
    address public owner;
    address public pendingOwner;
    address public operator;
    address public pendingOperator;
    bool public paused;
    uint256 private _tokenIdCounter;
    uint256 private constant _MAX_RENTAL_PERIOD = 365 days;
    uint256 private _reentrancyStatus;
    struct NftDetail { uint256 monthlyPrice; uint256 yearlyPrice; uint256 price; }
    struct UserInfo { address user; uint256 expires; }
    mapping(uint256 => NftDetail) private _nftDetails;
    mapping(uint256 => UserInfo) private _nftRenteeDetails;
    mapping(uint256 => address) private _tokenOwners;
    mapping(uint256 => string) private _tokenURIs;
    error NotOwner();
    error NotPendingOwner();
    error NotOperatorOrOwner();
    error NotPendingOperator();
    error PausedState();
    error NotPausedState();
    error ReentrantCall();
    error ZeroAddress();
    error AlreadyOwner();
    error AlreadyOperator();
    error EmptyURIs();
    error ArrayLengthMismatch();
    error EmptyURI();
    error InvalidRentalPeriod();
    error NFTAlreadyRented();
    error NFTDoesNotExist();
    error Unauthorized();
    error CannotTransferToSelf();
    error NFTIsRented();
    error NotTokenOwner(address from, address owner, uint256 tokenId);
    event OwnershipProposed(address indexed newOwner);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event OperatorProposed(address indexed newOperator);
    event OperatorUpdated(address indexed oldOperator, address indexed newOperator);
    event Paused(address account);
    event Unpaused(address account);
    event NFTMinted(uint256 indexed tokenId, address indexed to, string uri);
    event RentUpdate(uint256 indexed tokenId, address indexed user, uint256 expires);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event PricesUpdated(uint256 indexed tokenId, uint256 monthlyPrice, uint256 yearlyPrice, uint256 price);
    event TokenURIUpdated(uint256 indexed tokenId, string uri);
    modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }
    modifier onlyOperator() { if (msg.sender != operator && msg.sender != owner) revert NotOperatorOrOwner(); _; }
    modifier whenNotPaused() { if (paused) revert PausedState(); _; }
    modifier whenPaused() { if (!paused) revert NotPausedState(); _; }
    modifier nonReentrant() { if (_reentrancyStatus == 2) revert ReentrantCall(); _reentrancyStatus = 2; _; _reentrancyStatus = 1; }
    constructor() {
        address deployer = msg.sender;
        owner = deployer;
        operator = deployer;
        _tokenIdCounter = 1;
        _reentrancyStatus = 1;
        emit OwnershipTransferred(address(0), deployer);
        emit OperatorUpdated(address(0), deployer);
    }
    function proposeOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        if (newOwner == owner) revert AlreadyOwner();
        pendingOwner = newOwner;
        emit OwnershipProposed(newOwner);
    }
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, owner);
    }
    function proposeOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert ZeroAddress();
        if (newOperator == operator) revert AlreadyOperator();
        pendingOperator = newOperator;
        emit OperatorProposed(newOperator);
    }
    function acceptOperator() external {
        if (msg.sender != pendingOperator) revert NotPendingOperator();
        address oldOperator = operator;
        operator = pendingOperator;
        pendingOperator = address(0);
        emit OperatorUpdated(oldOperator, operator);
    }
    function pause() external onlyOwner whenNotPaused {
        paused = true;
        emit Paused(msg.sender);
    }
    function unpause() external onlyOwner whenPaused {
        paused = false;
        emit Unpaused(msg.sender);
    }
    function batchMint(string[] calldata uris, uint256[] calldata monthlyPrices, uint256[] calldata yearlyPrices, uint256[] calldata prices) external onlyOperator whenNotPaused nonReentrant {
        uint256 len = uris.length;
        if (len == 0) revert EmptyURIs();
        if (len != monthlyPrices.length || len != yearlyPrices.length || len != prices.length) revert ArrayLengthMismatch();
        uint256 idCounter = _tokenIdCounter;
        address contractOwner = owner;
        for (uint256 i = 0; i < len; i++) {
            if (bytes(uris[i]).length == 0) revert EmptyURI();
            uint256 id = idCounter;
            _tokenOwners[id] = contractOwner;
            _tokenURIs[id] = uris[i];
            _nftDetails[id] = NftDetail(monthlyPrices[i], yearlyPrices[i], prices[i]);
            emit NFTMinted(id, contractOwner, uris[i]);
            emit Transfer(address(0), contractOwner, id);
            unchecked { idCounter++; }
        }
        _tokenIdCounter = idCounter;
    }
    function rentNFT(uint256 tokenId, address user, uint256 expires) external onlyOperator whenNotPaused nonReentrant {
        if (user == address(0)) revert ZeroAddress();
        if (_tokenOwners[tokenId] == address(0)) revert NFTDoesNotExist();
        if (expires <= block.timestamp || expires > block.timestamp + _MAX_RENTAL_PERIOD) revert InvalidRentalPeriod();
        if (_nftRenteeDetails[tokenId].expires > block.timestamp) revert NFTAlreadyRented();
        _nftRenteeDetails[tokenId] = UserInfo(user, expires);
        emit RentUpdate(tokenId, user, expires);
    }
    function updateNFTPrices(uint256 tokenId, uint256 monthly, uint256 yearly, uint256 price) external onlyOperator whenNotPaused {
        if (_tokenOwners[tokenId] == address(0)) revert NFTDoesNotExist();
        _nftDetails[tokenId] = NftDetail(monthly, yearly, price);
        emit PricesUpdated(tokenId, monthly, yearly, price);
    }
    function setTokenURI(uint256 tokenId, string calldata uri) external whenNotPaused {
        address tokenOwner = _tokenOwners[tokenId];
        if (tokenOwner == address(0)) revert NFTDoesNotExist();
        if (bytes(uri).length == 0) revert EmptyURI();
        if (msg.sender != owner && msg.sender != operator && msg.sender != tokenOwner) revert Unauthorized();
        _tokenURIs[tokenId] = uri;
        emit TokenURIUpdated(tokenId, uri);
    }
    function secureTransferFrom(address from, address to, uint256 tokenId) external whenNotPaused nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (to == from) revert CannotTransferToSelf();
        address tokenOwner = _tokenOwners[tokenId];
        if (tokenOwner != from) revert NotTokenOwner(from, tokenOwner, tokenId);
        if (msg.sender != from && msg.sender != owner && msg.sender != operator) revert Unauthorized();
        if (_nftRenteeDetails[tokenId].expires > block.timestamp) revert NFTIsRented();
        _tokenOwners[tokenId] = to;
        delete _nftRenteeDetails[tokenId];
        emit Transfer(from, to, tokenId);
    }
    function ownerOf(uint256 tokenId) external view returns (address) {
        address tokenOwner = _tokenOwners[tokenId];
        if (tokenOwner == address(0)) revert NFTDoesNotExist();
        return tokenOwner;
    }
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (_tokenOwners[tokenId] == address(0)) revert NFTDoesNotExist();
        return _tokenURIs[tokenId];
    }
    function isRented(uint256 tokenId) external view returns (bool) {
        return _nftRenteeDetails[tokenId].expires > block.timestamp;
    }
    function getNftDetails(uint256 tokenId) external view returns (NftDetail memory) {
        if (_tokenOwners[tokenId] == address(0)) revert NFTDoesNotExist();
        return _nftDetails[tokenId];
    }
    function getRentalDetails(uint256 tokenId) external view returns (UserInfo memory) {
        if (_tokenOwners[tokenId] == address(0)) revert NFTDoesNotExist();
        return _nftRenteeDetails[tokenId];
    }
    function getNextTokenId() external view returns (uint256) {
        return _tokenIdCounter;
    }
}