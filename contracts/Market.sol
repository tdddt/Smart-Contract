// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

contract Market {
    // 상품 상태 : 판매 중, 거래 중, 거래 완료, 환불, 분쟁 중
    enum Status {
        OnSale,
        InTransaction,
        Completed,
        Refunded,
        Disputed
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
    }

    uint public itemCount; // 초기화 : 0
    mapping(uint => Item) public items;

    event ItemRegistered(uint indexed id, string name, address indexed seller); // 상품 등록 기록
    event ItemStatusChanged(uint indexed id, Status newStatus); // 상태 변경 기록 

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
            status:Status.OnSale;
        });

        emit ItemRegistered(itemCount, _name, msg.sender);
        emit ItemStatusChanged(itemCount, Status.OnSale);
    }

}