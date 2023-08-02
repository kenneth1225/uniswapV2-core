pragma solidity =0.5.16; //版本必须为0.5.16

import './interfaces/IUniswapV2Factory.sol'; //导入IunisawpV2Factory的interface合约
import './UniswapV2Pair.sol'; //导入Pair合约
//工厂合约
contract UniswapV2Factory is IUniswapV2Factory { //只继承了interface合约
    address public feeTo; //税收地址
    address public feeToSetter; //税收权限控制地址

    mapping(address => mapping(address => address)) public getPair; //地址对地址 查询两个代币的对子地址
    address[] public allPairs; //所有对子的地址数组

    event PairCreated(address indexed token0, address indexed token1, address pair, uint); //对子被创建的事件

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter; //构造函数部署时设置权限控制地址，可以是税收地址
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length; //获取数组长度
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) { //create2创建Pair合约
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES'); //tokenA和tokenB的地址不能相同
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA); //三元运算进行排序
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS'); //token0不能是零地址
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); //用映射确定token0和token1没有创建过对子
        bytes memory bytecode = type(UniswapV2Pair).creationCode; //局部变量来获取Pair合约的字节码
        bytes32 salt = keccak256(abi.encodePacked(token0, token1)); //局部变量创建盐，用keccak256将token0和token1进行哈希打包
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt) //内联汇编进行部署，并将部署好的Pair合约赋值给pair地址
        }
        IUniswapV2Pair(pair).initialize(token0, token1); //调用Pair合约中的initialize方法进行初始化参数
        getPair[token0][token1] = pair; //token0和token1得出映射的对子地址
        getPair[token1][token0] = pair; //相反也可以得出映射的对子地址
        allPairs.push(pair); //将创建的对子地址推入数组
        emit PairCreated(token0, token1, pair, allPairs.length); //触发创建事件
    }

    function setFeeTo(address _feeTo) external { //设置新的收税人地址
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN'); //调用者必须为税收权限控制者
        feeTo = _feeTo; //更新状态变量
    }

    function setFeeToSetter(address _feeToSetter) external { //设置新的税收权限控制者
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN'); //调用者必须为收税权限控制者
        feeToSetter = _feeToSetter; //更新状态变量
    }
}
