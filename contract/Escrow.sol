// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Escrow - depot securise entre acheteur et vendeur (ETH ou ERC20 comme USDC)
contract Escrow is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant DEFAULT_OWNER = 0x30Ed1738Dc49BC50b814a3a274e5571F9960D036;
    address public constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    uint256 public constant MAX_FEE_BPS = 500; // 5 %
    uint256 public constant BPS = 10_000;

    enum Status { None, Funded, Disputed, Released, Refunded }

    struct Deal {
        address buyer;
        address seller;
        address token; // address(0) = ETH
        uint256 amount;
        uint256 feeBps; // fige a la creation
        uint64 deadline; // 0 = pas de delai
        Status status;
    }

    uint256 public feeBps = 200; // 2 %
    address public feeRecipient;
    uint256 public dealCount;
    mapping(uint256 => Deal) public deals;
    mapping(address => bool) public allowedToken;

    event DealCreated(uint256 indexed id, address indexed buyer, address indexed seller, address token, uint256 amount, uint64 deadline);
    event Released(uint256 indexed id, uint256 toSeller, uint256 fee);
    event Refunded(uint256 indexed id, uint256 amount);
    event Disputed(uint256 indexed id, address by);
    event FeeUpdated(uint256 feeBps);
    event FeeRecipientUpdated(address recipient);
    event TokenAllowed(address token, bool allowed);

    error InvalidParams();
    error NotAuthorized();
    error BadStatus();
    error TooEarly();
    error FeeTooHigh();
    error EthTransferFailed();

    constructor() Ownable(DEFAULT_OWNER) {
        feeRecipient = DEFAULT_OWNER;
        allowedToken[address(0)] = true; // ETH
        allowedToken[USDC_BASE] = true;
    }

    // ---------- Admin ----------
    function setFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh();
        feeBps = newFeeBps;
        emit FeeUpdated(newFeeBps);
    }

    function setFeeRecipient(address r) external onlyOwner {
        if (r == address(0)) revert InvalidParams();
        feeRecipient = r;
        emit FeeRecipientUpdated(r);
    }

    function setAllowedToken(address token, bool allowed) external onlyOwner {
        allowedToken[token] = allowed;
        emit TokenAllowed(token, allowed);
    }

    // ---------- Creation ----------
    function createDealETH(address seller, uint64 deadline) external payable nonReentrant returns (uint256) {
        if (!allowedToken[address(0)]) revert InvalidParams();
        return _create(seller, address(0), msg.value, deadline);
    }

    function createDealToken(address token, address seller, uint256 amount, uint64 deadline)
        external nonReentrant returns (uint256)
    {
        if (token == address(0) || !allowedToken[token]) revert InvalidParams();
        uint256 before = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - before;
        return _create(seller, token, received, deadline);
    }

    function _create(address seller, address token, uint256 amount, uint64 deadline) internal returns (uint256 id) {
        if (seller == address(0) || seller == msg.sender || amount == 0) revert InvalidParams();
        if (deadline != 0 && deadline <= block.timestamp) revert InvalidParams();
        id = ++dealCount;
        deals[id] = Deal(msg.sender, seller, token, amount, feeBps, deadline, Status.Funded);
        emit DealCreated(id, msg.sender, seller, token, amount, deadline);
    }

    // ---------- Actions ----------
    /// L'acheteur confirme la reception -> paiement du vendeur
    function confirm(uint256 id) external nonReentrant {
        Deal storage d = deals[id];
        if (msg.sender != d.buyer) revert NotAuthorized();
        if (d.status != Status.Funded) revert BadStatus();
        _release(id, d);
    }

    /// Le vendeur reclame apres le delai si l'acheteur n'a rien fait (et pas de litige)
    function claimAfterDeadline(uint256 id) external nonReentrant {
        Deal storage d = deals[id];
        if (msg.sender != d.seller) revert NotAuthorized();
        if (d.status != Status.Funded) revert BadStatus();
        if (d.deadline == 0 || block.timestamp < d.deadline) revert TooEarly();
        _release(id, d);
    }

    /// Le vendeur peut rembourser volontairement l'acheteur
    function sellerRefund(uint256 id) external nonReentrant {
        Deal storage d = deals[id];
        if (msg.sender != d.seller) revert NotAuthorized();
        if (d.status != Status.Funded && d.status != Status.Disputed) revert BadStatus();
        _refund(id, d);
    }

    /// Acheteur ou vendeur ouvre un litige (bloque le delai)
    function openDispute(uint256 id) external {
        Deal storage d = deals[id];
        if (msg.sender != d.buyer && msg.sender != d.seller) revert NotAuthorized();
        if (d.status != Status.Funded) revert BadStatus();
        d.status = Status.Disputed;
        emit Disputed(id, msg.sender);
    }

    /// L'arbitre (owner) tranche un litige
    function resolveDispute(uint256 id, bool releaseToSeller) external onlyOwner nonReentrant {
        Deal storage d = deals[id];
        if (d.status != Status.Disputed) revert BadStatus();
        if (releaseToSeller) _release(id, d);
        else _refund(id, d);
    }

    // ---------- Internes (checks-effects-interactions) ----------
    function _release(uint256 id, Deal storage d) internal {
        d.status = Status.Released;
        uint256 fee = (d.amount * d.feeBps) / BPS;
        uint256 net = d.amount - fee;
        if (fee > 0) _pay(d.token, feeRecipient, fee);
        _pay(d.token, d.seller, net);
        emit Released(id, net, fee);
    }

    function _refund(uint256 id, Deal storage d) internal {
        d.status = Status.Refunded;
        _pay(d.token, d.buyer, d.amount);
        emit Refunded(id, d.amount);
    }

    function _pay(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            (bool ok,) = payable(to).call{value: amount}("");
            if (!ok) revert EthTransferFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }
}
