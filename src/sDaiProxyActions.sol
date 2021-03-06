pragma solidity ^0.5.10;

contract DSTokenLike {
    function mint(address,uint) external;
    function burn(address,uint) external;
    function approve(address usr, uint wad) external;
    function transfer(address, uint) public;
    function transferFrom(address, address, uint) public;
    function balanceOf(address) public returns (uint);
}

contract VatLike{
    function dai(address) public view returns (uint);
    function can(address, address) public view returns (uint);
    function hope(address) public;
}

contract PotLike{
    function chi() public view returns (uint);
    function drip() public;
}

contract DaiJoinLike {
    function vat() public returns (VatLike);
    function dai() public returns (DSTokenLike);
    function join(address, uint) public payable;
    function exit(address, uint) public;
}

contract SavingsJoinLike {
    function pot() public returns(PotLike);
    function vat() public returns(VatLike);
    function sDai() public returns(DSTokenLike);
    function join(address, uint) external;
    function exit(address, uint) external;
}


contract JugLike {
    function drip(bytes32) public;
}

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! //
// WARNING: These functions meant to be used as a a library for a DSProxy. Some are unsafe if you call them directly. //
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! //

contract sDaiProxyActions {

    uint256 constant ONE = 10 ** 27;

    // Internal functions
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "mul-overflow");
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "sub-overflow");
    }

    function toInt(uint x) internal pure returns (int y) {
        y = int(x);
        require(y >= 0, "int-overflow");
    }

    function toWad(uint rad) internal pure returns (uint wad) {
        wad = rad / ONE;
    }

    function toRad(uint wad) internal pure returns (uint rad) {
        rad = mul(wad, ONE);
    }

    function daiJoin_join(address apt, address urn, uint wad) public {
        // Gets DAI from the user's wallet
        DaiJoinLike(apt).dai().transferFrom(msg.sender, address(this), wad);
        // Approves adapter to take the DAI amount
        DaiJoinLike(apt).dai().approve(apt, wad);
        // Joins DAI into the vat
        DaiJoinLike(apt).join(urn, wad);
    }

    function sDaiJoin(
        address daiJoin,
        address savingsJoin,
        uint wad
    ) public {
        VatLike vat = SavingsJoinLike(savingsJoin).vat();
        PotLike pot = SavingsJoinLike(savingsJoin).pot();
        // Executes drip to get the chi rate updated to rho == now, otherwise join will fail
        pot.drip();
        // Joins wad amount to the vat balance
        daiJoin_join(daiJoin, address(this), wad);
        // Approves the adapter to take out DAI from the proxy's balance in the vat
        if (vat.can(address(this), address(savingsJoin)) == 0) {
            vat.hope(savingsJoin);
        }
        // Exits the wad value (equivalent to the DAI wad amount) to Savings Dai
        SavingsJoinLike(savingsJoin).exit(address(this), mul(wad, ONE) / pot.chi());
    }

    function sDaiExit(
        address daiJoin,
        address savingsJoin,
        uint wad
    ) public {
        VatLike vat = SavingsJoinLike(savingsJoin).vat();
        PotLike pot = SavingsJoinLike(savingsJoin).pot();
        DSTokenLike sDai = SavingsJoinLike(savingsJoin).sDai();
        // Executes drip to count the savings accumulated until this moment
        pot.drip();
        // Calculates the pie value in the pot equivalent to the DAI wad amount
        uint pie = mul(wad, ONE) / pot.chi();
        // Exits DAI from the sDai
        sDai.approve(savingsJoin, pie);
        SavingsJoinLike(savingsJoin).join(address(this), pie);
        // Checks the actual balance of DAI in the vat after the pot exit
        uint bal = vat.dai(address(this));
        // Allows adapter to access to proxy's DAI balance in the vat
        if (vat.can(address(this), daiJoin) == 0) {
            vat.hope(daiJoin);
        }
        // It is necessary to check if due rounding the exact wad amount can be exited by the adapter.
        // Otherwise it will do the maximum DAI balance in the vat
        DaiJoinLike(daiJoin).exit(
            msg.sender,
            bal >= mul(wad, ONE) ? wad : bal / ONE
        );
    }

    function sDaiExitAll(
        address daiJoin,
        address savingsJoin
    ) public {
        VatLike vat = SavingsJoinLike(savingsJoin).vat();
        PotLike pot = SavingsJoinLike(savingsJoin).pot();
        DSTokenLike sDai = SavingsJoinLike(savingsJoin).sDai();
        // Executes drip to count the savings accumulated until this moment
        pot.drip();
        // Gets the total sDai belonging to the proxy address
        uint pie = sDai.balanceOf(address(this));
        // Exits DAI from the sDai
        sDai.approve(savingsJoin, pie);
        // Join Savings Dai back into the Vat
        SavingsJoinLike(savingsJoin).join(address(this), pie);
        // Allows adapter to access to proxy's DAI balance in the vat
        if (vat.can(address(this), address(daiJoin)) == 0) {
            vat.hope(daiJoin);
        }
        DaiJoinLike(daiJoin).exit(
            msg.sender,
            mul(PotLike(pot).chi(), pie) / ONE
        );
    }
}
