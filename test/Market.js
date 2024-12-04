const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Market Contract", function () {
  let market;
  let admin;
  let seller;
  let buyer;
  let otherAccount;

  beforeEach(async function () {
    [admin, seller, buyer, otherAccount] = await ethers.getSigners();

    const Market = await ethers.getContractFactory("Market");
    market = await Market.deploy();
  });

  // 배포
  describe("Deployment", function () {
    it("Should set the admin correctly", async function () {
      expect(await market.admin()).to.equal(admin.address);
    });
  });

  // 등록
  describe("Register Item", function () {
    it("Should register an item successfully", async function () {
      await market.connect(seller).registerItem("Item1", "Description", 100);

      const item = await market.getItem(1);
      expect(item.name).to.equal("Item1");
      expect(item.price).to.equal(100);
      expect(item.status).to.equal(0); // OnSale
    });

    it("Should emit ItemRegistered event on item registration", async function () {
      await expect(market.connect(seller).registerItem("Item2", "Description", 200))
        .to.emit(market, "ItemRegistered")
        .withArgs(1, "Item2", seller.address);
    });
  });
  
  // 아이템 조회
  describe("Get Item", function () {
    beforeEach(async function () {
      await market.connect(seller).registerItem("Item1", "Description", 100);
      await market.connect(seller).registerItem("Item2", "Another Description", 200);
    });
  
    it("Should retrieve seller's items correctly", async function () {
      const sellerItems = await market.getItemBySeller(seller.address);
      expect(sellerItems.length).to.equal(2);
      expect(sellerItems[0]).to.equal(1);
      expect(sellerItems[1]).to.equal(2);
    });
  
    it("Should return empty array for seller with no items", async function () {
      const otherSellerItems = await market.getItemBySeller(otherAccount.address);
      expect(otherSellerItems.length).to.equal(0);
    });
  
    it("Should retrieve an item by ID correctly", async function () {
      const item = await market.getItem(1);
      expect(item.name).to.equal("Item1");
      expect(item.desc).to.equal("Description");
      expect(item.price).to.equal(100);
      expect(item.seller).to.equal(seller.address);
    });
  });

  // 구매
  describe("Buy Item", function () {
    beforeEach(async function () {
      await market.connect(seller).registerItem("Item1", "Description", 100);
    });

    it("Should allow a buyer to buy an item", async function () {
      await market.connect(buyer).buyItem(1, { value: 100 });

      const item = await market.getItem(1);
      expect(item.buyer).to.equal(buyer.address);
      expect(item.status).to.equal(1); // InTransaction
    });

    it("Should emit ItemBought event on purchase", async function () {
      await expect(market.connect(buyer).buyItem(1, { value: 100 }))
        .to.emit(market, "ItemBought")
        .withArgs(1, buyer.address, 100);
    });

    it("Should fail if the buyer sends less than the price", async function () {
      await expect(market.connect(buyer).buyItem(1, { value: 50 }))
        .to.be.revertedWith("판매 가격보다 낮은 가격으로 구매할 수 없습니다.");
    });

    it("Should fail if the buyer is the seller", async function () {
      await expect(market.connect(seller).buyItem(1, { value: 100 }))
        .to.be.revertedWith("본인의 상품을 구매할 수 없습니다.");
    });
  });

  // 존재하지 않는 아이템 구매 시도
  describe("Non-existent Item Purchase", function () {
    it("Should fail when trying to buy a non-existent item", async function () {
      // Trying to buy an item with ID 999 which doesn't exist
      await expect(market.connect(buyer).buyItem(999, { value: 100 }))
        .to.be.revertedWith("존재하지 않는 상품입니다.");
    });
  
    it("Should fail when trying to request refund for a non-existent item", async function () {
      await expect(market.connect(buyer).requestRefund(999))
        .to.be.reverted; // The specific revert reason depends on the contract's implementation
    });
  });

  // 구매 확정
  describe("Confirm Item", function () {
    beforeEach(async function () {
      await market.connect(seller).registerItem("Item1", "Description", 100);
      await market.connect(buyer).buyItem(1, { value: 100 });
    });
  
    it("Should allow buyer to confirm item", async function () {
      await market.connect(buyer).confirmItem(1);
  
      const item = await market.getItem(1);
      expect(item.status).to.equal(2); // Completed
    });
  
    it("Should fail if not called by buyer", async function () {
      await expect(market.connect(seller).confirmItem(1))
        .to.be.revertedWith("구매자만 거래를 완료할 수 있습니다.");
    });
  
    it("Should fail if item is not in transaction", async function () {
      // First confirm the item
      await market.connect(buyer).confirmItem(1);
  
      // Then try to confirm again
      await expect(market.connect(buyer).confirmItem(1))
        .to.be.revertedWith("거래 중인 상태가 아닙니다.");
    });
  });

  // 환불 요청
  describe("Request Refund", function () {
    beforeEach(async function () {
      await market.connect(seller).registerItem("Item1", "Description", 100);
      await market.connect(buyer).buyItem(1, { value: 100 });
    });

    it("Should allow buyer to request refund", async function () {
      await market.connect(buyer).requestRefund(1);

      const item = await market.getItem(1);
      expect(item.status).to.equal(4); // RefundRequested
    });

    it("Should emit RefundRequested event on refund request", async function () {
      await expect(market.connect(buyer).requestRefund(1))
        .to.emit(market, "RefundRequested")
        .withArgs(1, buyer.address);
    });

    it("Should fail if the refund is requested when not in transaction", async function () {
      await expect(market.connect(buyer).requestRefund(2))
        .to.be.revertedWith("거래 중인 상태가 아닙니다.");
    });
  });

  // 환불 승인
  describe("Approve Refund", function () {
    beforeEach(async function () {
      await market.connect(seller).registerItem("Item1", "Description", 100);
      await market.connect(buyer).buyItem(1, { value: 100 });
      await market.connect(buyer).requestRefund(1);
    });

    it("Should allow seller to approve refund", async function () {
      await market.connect(seller).approveRefund(1);

      const item = await market.getItem(1);
      expect(item.status).to.equal(3); // Refunded
    });

    it("Should emit RefundApproved event on approval", async function () {
      await expect(market.connect(seller).approveRefund(1))
        .to.emit(market, "RefundApproved")
        .withArgs(1, seller.address);
    });

    it("Should fail if the seller is not the one requesting approval", async function () {
      await expect(market.connect(buyer).approveRefund(1))
        .to.be.revertedWith("판매자만 환불을 승인할 수 있습니다.");
    });
  });

  // 환불 거절
  describe("Refuse Refund", function () {
    beforeEach(async function () {
      await market.connect(seller).registerItem("Item1", "Description", 100);
      await market.connect(buyer).buyItem(1, { value: 100 });
      await market.connect(buyer).requestRefund(1);
    });
  
    it("Should allow seller to refuse refund", async function () {
      await market.connect(seller).refuseRefund(1);
  
      const item = await market.getItem(1);
      expect(item.status).to.equal(5); // Disputed
    });
  
    it("Should emit RefundRefused event on refund refusal", async function () {
      await expect(market.connect(seller).refuseRefund(1))
        .to.emit(market, "RefundRefused")
        .withArgs(1, seller.address);
    });
  
    it("Should fail if not called by seller", async function () {
      await expect(market.connect(buyer).refuseRefund(1))
        .to.be.revertedWith("판매자만 환불을 승인할 수 있습니다.");
    });
  
    it("Should fail if refund is not in RefundRequested state", async function () {
      await market.connect(seller).registerItem("Item2", "Description", 200);
      await market.connect(buyer).buyItem(2, { value: 200 });
  
      await expect(market.connect(seller).refuseRefund(2))
        .to.be.revertedWith("환불 요청 상태가 아닙니다.");
    });
  
    it("Should change item status to Disputed after refund refusal", async function () {
      await market.connect(seller).refuseRefund(1);
  
      await expect(market.connect(admin).resolveDispute(1, true, "Test Dispute"))
        .to.emit(market, "DisputeResolved")
        .withArgs(1, admin.address, "Refunded", "Test Dispute");
    });
  });

  // 논쟁 해결
  describe("Resolve Dispute", function () {
    beforeEach(async function () {
      // 아이템 등록 및 구매, 환불 요청, 환불 거절
      await market.connect(seller).registerItem("Item1", "Description", 100);
      await market.connect(buyer).buyItem(1, { value: 100 });
      await market.connect(buyer).requestRefund(1);
      await market.connect(seller).refuseRefund(1);
    });
  
    it("Should allow admin to resolve dispute and approve refund", async function () {
      await market.connect(admin).resolveDispute(1, true, "Refund Approved");
  
      const item = await market.getItem(1);
      expect(item.status).to.equal(6); // DisputedResolved
    });
  
    it("Should allow admin to resolve dispute and reject refund", async function () {
      await market.connect(admin).resolveDispute(1, false, "Refund Rejected");
  
      const item = await market.getItem(1);
      expect(item.status).to.equal(6); // DisputedResolved
    });
  
    it("Should emit DisputeResolved event on resolution (refund approved)", async function () {
      await expect(market.connect(admin).resolveDispute(1, true, "Refund Approved"))
        .to.emit(market, "DisputeResolved")
        .withArgs(1, admin.address, "Refunded", "Refund Approved");
    });
  
    it("Should emit DisputeResolved event on resolution (refund rejected)", async function () {
      await expect(market.connect(admin).resolveDispute(1, false, "Refund Rejected"))
        .to.emit(market, "DisputeResolved")
        .withArgs(1, admin.address, "Completed", "Refund Rejected");
    });
  
    it("Should fail if non-admin tries to resolve dispute", async function () {
      await expect(market.connect(seller).resolveDispute(1, true, "Refund Approved"))
        .to.be.revertedWith("관리자만 접근 가능합니다.");
    });
  });  
});
