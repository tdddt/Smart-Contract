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
        uint256 id; // 아이디 자동 증가
        string name;
        string desc;
        uint256 price;
        address seller;
        address buyer;
        Status status;
        uint256 escrow; // 예치금 = 최종 거래 금액
        uint256 rating; // 거래 별점
        bool rated; // 별점 남겼는지 여부
    }

    uint256 public itemCount; // 초기화 : 0

    // itemId(상품 Id) => Item(상품 정보)
    mapping(uint256 => Item) public items;

    // seller address(판매자 주소) => itemIds(판매한 상품 아이디)
    mapping(address => uint256[]) public sellerItems; // 판매한 상품

    // buyer address(구매자 주소) => itemIds(구매한 상품 아이디)
    mapping(address => uint256[]) public buyerItems; // 구매한 상품
    
    event ItemRegistered(uint256 indexed id, string name, address indexed seller); // 상품 등록 기록
    event ItemStatusChanged(uint256 indexed id, Status newStatus); // 상태 변경 기록 
    event ItemBought(uint256 indexed id, address indexed buyer, uint256 price); // 상품 구매 기록
    event RefundRequested(uint256 indexed id, address indexed buyer, string reason); // 환불 요청 기록
    event RefundApproved(uint256 indexed id, address indexed seller); // 환불 처리 기록
    event RefundRefused(uint256 indexed id, address indexed seller, string reason); // 환불 거절 기록 -> 분쟁 기록
    event DisputeResolved(uint256 indexed id, address indexed resolver, string action, string reason); // 분쟁 해결 기록

    address public admin; // 분쟁 관리자

    // uint public constant ADMIN_FEE_PERCENTAGE = 2; // 분쟁 해결 시 2% 수수료 고민해보기

    modifier onlyAdmin(){
        require(msg.sender == admin, unicode"관리자만 접근 가능합니다.");
        _;
    }

    constructor() { // 초기 관리자 설정 = 배포자
        admin = msg.sender;
    }

    // 상품 등록
    function registerItem(string memory _name, string memory _desc, uint256 _price) public {
        require(bytes(_name).length > 0, unicode"상품 이름을 입력해야 합니다.");
        require(_price > 0 ,unicode"가격은 0보다 커야 합니다.");

        itemCount++; // 아이디 자동 증가 (1부터 시작)
        items[itemCount] = Item({
            id:itemCount,
            name:_name,
            desc:_desc,
            price:_price,
            seller:msg.sender,
            buyer:address(0),
            status:Status.OnSale,
            escrow:0,
            rating:0,
            rated:false
        });

        sellerItems[msg.sender].push(itemCount); // 판매 상품

        emit ItemRegistered(itemCount, _name, msg.sender);
        emit ItemStatusChanged(itemCount, Status.OnSale);
    }

    // 아이디로 상품 조회
    function getItem(uint256 _id) public view returns (Item memory){
        require(_id > 0 && _id <= itemCount, unicode"존재하지 않는 상품입니다.");
        return items[_id];
    }

    // 판매자로 상품 조회
    function getItemBySeller(address seller) public view returns (uint256[] memory) {
        require(seller != address(0), unicode"해당 주소의 판매자를 찾을 수 없습니다.");
        return sellerItems[seller];
    }

    // 구매한 상품 조회
    function getItemAsBuyer(address buyer) public view returns (uint256[] memory) {
        require(buyer != address(0), unicode"해당 주소의 구매자를 찾을 수 없습니다.");
        return buyerItems[buyer];
    }

    // 상품 구매
    function buyItem(uint256 _id) public payable {
        require(_id > 0 && _id <= itemCount, unicode"존재하지 않는 상품입니다.");
        Item storage item = items[_id];
        require(item.status == Status.OnSale, unicode"판매 중인 상품만 구매할 수 있습니다.");
        require(msg.value >= item.price, unicode"판매 가격보다 낮은 가격으로 구매할 수 없습니다."); // 가스비 고려
        require(msg.sender != item.seller, unicode"본인의 상품을 구매할 수 없습니다.");

        item.buyer = msg.sender;
        item.escrow = msg.value; // 최종 거래 금액 (가스비 별도로 처리되는지 확인하기)
        item.status = Status.InTransaction;
        buyerItems[msg.sender].push(_id); // 구매자 아이템 추가

        emit ItemBought(_id, msg.sender, item.escrow);
        emit ItemStatusChanged(_id, Status.InTransaction);
    }

    // 구매 확정
    function confirmItem(uint256 _id) public {
        Item storage item = items[_id];
        require(item.status == Status.InTransaction,unicode"거래 중인 상태가 아닙니다.");
        require(msg.sender == item.buyer, unicode"구매자만 거래를 완료할 수 있습니다.");

        // payable(item.seller).transfer(item.escrow);
        item.status = Status.Completed;

        (bool success, ) = item.seller.call{value: item.escrow}("");
        require(success, unicode"판매자에게 송금 실패");

        // 평점 등록
        emit ItemStatusChanged(_id, Status.Completed);
    }

    // 환불 요청
    function requestRefund(uint256 _id, string memory reason) public {
        Item storage item = items[_id];
        require(item.status == Status.InTransaction, unicode"거래 중인 상태가 아닙니다.");
        require(msg.sender == item.buyer,unicode"구매자만 환불을 요청할 수 있습니다.");
        require(bytes(reason).length > 0, unicode"환불 요청 사유를 입력해야 합니다.");

        item.status = Status.RefundRequested;

        emit RefundRequested(_id, msg.sender,reason);
        emit ItemStatusChanged(_id, Status.RefundRequested);
    }

    // 환불 승인
    function approveRefund(uint256 _id) public {
        Item storage item = items[_id];
        require(item.status == Status.RefundRequested,unicode"환불 요청 상태가 아닙니다.");
        require(msg.sender == item.seller,unicode"판매자만 환불을 승인할 수 있습니다.");

        // payable(item.buyer).transfer(item.escrow); // 예치금 환불 -> 가스비 문제 고려
        item.status = Status.Refunded;

        (bool success, ) = item.buyer.call{value: item.escrow}("");
        require(success, unicode"구매자에게 환불 실패");

        emit RefundApproved(_id, msg.sender);
        emit ItemStatusChanged(_id, Status.Refunded);
    }

    // 환불 거절
    function refuseRefund(uint256 _id, string memory reason) public {
        Item storage item = items[_id];
        require(item.status == Status.RefundRequested,unicode"환불 요청 상태가 아닙니다.");
        require(msg.sender == item.seller,unicode"판매자만 환불을 승인할 수 있습니다.");
        require(bytes(reason).length > 0, unicode"환불 거절 사유를 입력해야 합니다.");

        item.status = Status.Disputed;

        emit RefundRefused(_id, msg.sender,reason);
        emit ItemStatusChanged(_id, Status.Disputed);
    }

    // 분쟁 해결
    function resolveDispute(uint256 _id, bool approve, string memory reason) public onlyAdmin {
        Item storage item = items[_id];
        require(item.status == Status.Disputed, unicode"분쟁 상태가 아닙니다. 분쟁 상태만 관리자가 관여할 수 있습니다.");
    
        if(approve) { // 구매자에게 환불
            item.status = Status.DisputedResolved;
            (bool success, ) = item.buyer.call{value: item.escrow}("");
            require(success, unicode"구매자에게 환불 실패");
        } else { // 판매자에게 금액 전송
            item.status = Status.DisputedResolved;
            (bool success, ) = item.seller.call{value: item.escrow}("");
            require(success, unicode"판매자에게 송금 실패");
        }
        emit DisputeResolved(_id, msg.sender, approve? "Refunded" : "Completed", reason);
    }

    // // 별점
    // function rateTransaction(uint _id, uint256 _rating) external {
    //     Item storage item = items[_id];

    //     require(msg.sender == item.buyer,unicode"구매자만 평점을 남길 수 있습니다.");
    //     require(item.status == Status.Completed || item.status == Status.Refunded || item.status == Status.DisputedResolved, "아직 평점을 남길 수 없습니다." );
    //     require(_rating >=1 && _rating<=5,unicode"평점은 1-5 사이의 숫자여야 합니다.");
    //     require(item.rated==false, unicode"이미 평점을 남겼습니다.");

    //     item.rating = _rating;
    //     item.rated = true;
    // }
}