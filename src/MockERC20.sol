// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./IERC20.sol";

contract MockERC20 is IERC20 {
    string public name; string public symbol; uint8 public decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    constructor(string memory n, string memory s){ name=n; symbol=s; }
    function mint(address to, uint256 v) external { balanceOf[to]+=v; totalSupply+=v; emit Transfer(address(0),to,v); }
    function transfer(address to, uint256 v) external returns(bool){ balanceOf[msg.sender]-=v; balanceOf[to]+=v; emit Transfer(msg.sender,to,v); return true; }
    function approve(address sp, uint256 v) external returns(bool){ allowance[msg.sender][sp]=v; emit Approval(msg.sender,sp,v); return true; }
    function transferFrom(address f,address t,uint256 v) external returns(bool){
        uint256 a=allowance[f][msg.sender]; require(a>=v,"allowance"); if(a!=type(uint256).max) allowance[f][msg.sender]=a-v;
        balanceOf[f]-=v; balanceOf[t]+=v; emit Transfer(f,t,v); return true;
    }
}
