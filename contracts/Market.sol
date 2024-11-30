// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

contract Market {
    // 상품 상태 : 판매 중, 거래 중, 거래 완료, 환불 요청, 환불, 분쟁 중, 분쟁 종료
    enum Status {
        OnSale,
        InTransaction,
        Completed,
        Refunded,
        RefundRequested,
        Disputed,
        DisputedResolved
    }

    // 판매 상품 : 아이디, 이름, 설명, 가격, 판매자, 구매자, 상태
    struct Item {
        uint id; // 아이디 자동 증가
        string name;
        string desc;
        uint price;
        address seller;
        address buyer;
        Status status;
        uint escrow; // 예치금 = 최종 거래 금액
    }

    uint public itemCount; // 초기화 : 0
    mapping(uint => Item) public items;
    mapping(address => uint[]) public sellerItems; // 판매한 상품
    mapping(address => uint[]) public buyerItems; // 구매한 상품
    
    event ItemRegistered(uint indexed id, string name, address indexed seller); // 상품 등록 기록
    event ItemStatusChanged(uint indexed id, Status newStatus); // 상태 변경 기록 
    event ItemBuyed(uint indexed id, address indexed buyer, int price); // 상품 구매 기록
    event RefundRequested(uint indexed id, address indexed buyer); // 환불 요청 기록
    event RefundApproved(uint indexed id, address indexed seller); // 환불 처리 기록
    event RefundRefused(uint indexed id, address indexed seller); // 환불 거절 기록 -> 분쟁 기록

    // 상품 등록
    function registerItem(string memory _name, string memory _desc, uint _price) public {
        require(_price > 0 ,"가격은 0보다 커야 합니다.");

        itemCount++; // 아이디 자동 증가 (1부터 시작)
        items[itemCount] = Item({
            id:itemCount,
            name:_name,
            desc:_desc,
            price:_price,
            seller:msg.sender,
            buyer:address(0),
            status:Status.OnSale,
            escrow:0
        });

        sellerItems[msg.sender].push(itemCount); // 판매 상품

        emit ItemRegistered(itemCount, _name, msg.sender);
        emit ItemStatusChanged(itemCount, Status.OnSale);
    }

    // 아이디로 상품 조회
    function getItem(uint _id) public view returns (Item memory){
        return items[_id];
    }

    // 판매자로 상품 조회
    function getItemBySeller(address seller) public view returns (uint[] memory) {
        return sellerItems[seller];
    }

    // 구매한 상품 조회
    function getItemAsBuyer(address buyer) public view returns (uint[] memory) {
        return buyerItems[buyer];
    }

    // 상품 구매
    function buyItem(uint _id) public payable {
        Item storage item = items[_id];
        require(item.status == Status.OnSale, "판매 중인 상품만 구매할 수 있습니다.");
        require(msg.value >= item.price, "판매 가격보다 낮은 가격으로 구매할 수 없습니다."); // 가스비 고려
        require(msg.sender != item.seller, "본인의 상품을 구매할 수 없습니다.");

        item.buyer = msg.sender;
        item.escrow = msg.value; // 최종 거래 금액
        item.status = Status.InTransaction;
        buyerItems[msg.sender].push(_id); // 구매자 아이템 추가

        emit ItemBuyed(_id, msg.sender, item.price);
        emit ItemStatusChanged(_id, Status.InTransaction);
    }

    // 구매 확정
    function confirmItem(uint _id) public {
        Item storage item = items[_id];
        require(item.status == Status.InTransaction, "거래 중인 상태가 아닙니다.");
        require(msg.sender == item.buyer, "구매자만 거래를 완료할 수 있습니다.");

        payable(item.seller).transfer(item.escrow);
        item.status = status.Completed;

        // 평점 등록

        emit ItemStatusChanged(_id, Status.Completed);
    }

    // 환불 요청
    function requestRefund(uint _id) public {
        Item storage item = items[_id];
        require(item.status == Status.InTransaction, "거래 중인 상태가 아닙니다.");
        require(msg.sender == item.buyer,"구매자만 환불을 요청할 수 있습니다.");

        item.status = Status.RefundRequested;

        emit RefundRequested(_id, msg.sender);
        emit ItemStatusChanged(_id, Status.RefundRequested);
    }
}