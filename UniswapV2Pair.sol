pragma solidity =0.5.16; //版本必须为0.5.16

import './interfaces/IUniswapV2Pair.sol'; //导入IUniswapV2Pair的interface
import './UniswapV2ERC20.sol'; //导入ERC20合约
import './libraries/Math.sol'; //导入数学合约
import './libraries/UQ112x112.sol'; //导入算法
import './interfaces/IERC20.sol'; //导入IERC20的interface
import './interfaces/IUniswapV2Factory.sol'; //导入IUniswapV2Factory的interface
import './interfaces/IUniswapV2Callee.sol'; //导入IUniswapV2Callee的interface

contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 { //只继承了IUniswapPair和ERC20合约
    using SafeMath  for uint; //把数学库赋值给本合约的uint256
    using UQ112x112 for uint224; //把算法库赋值给本合约的uint224

    uint public constant MINIMUM_LIQUIDITY = 10**3; //最小流动性为1000
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)'))); //获得transfer的selector

    address public factory; // 工厂合约地址
    address public token0; //token0地址
    address public token1; //token1地址

    uint112 private reserve0; //储备量0
    uint112 private reserve1; //储备量1
    uint32  private blockTimestampLast; //时间戳

    uint public price0CumulativeLast; //价格0最后累计
    uint public price1CumulativeLast; //价格1最后累计
    uint public kLast; //x*y=k公式的k值

    uint private unlocked = 1; //重入锁默认值为1

    modifier lock() { //重入锁
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }
    //获取储备量
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private { //安全发送
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'UniswapV2: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1); //铸造事件
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to); //销毁事件
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    ); //交换事件
    event Sync(uint112 reserve0, uint112 reserve1); //同步事件

    constructor() public {
        factory = msg.sender; //初始化factory合约地址
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external { //初始化token0和token1的地址
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN'); //调用者必须是factory地址
        token0 = _token0; //更新变量
        token1 = _token1; //更新变量
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'UniswapV2: OVERFLOW'); //确认余额0和余额1为uint112的最大值
        uint32 blockTimestamp = uint32(block.timestamp % 2**32); //将时间戳转换为uint32
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; //计算时间流逝
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) { //如果时间流逝大于0，储备量0和储备量1都大于0
            //价格0最后累计 += 储备量1 * 2 ** 112 / 储备量0 * 时间流逝
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            //价格1最后累计 += 储备量0 * 2 ** 112 / 储备量1 * 时间流逝
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0); //余额0放入储备量0
        reserve1 = uint112(balance1); //余额1放入储备量1
        blockTimestampLast = blockTimestamp; //计算最后时间戳
        emit Sync(reserve0, reserve1); //触发同步事件
    }

    //铸造费的方法
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IUniswapV2Factory(factory).feeTo(); //查看工厂合约的feeTo变量
        feeOn = feeTo != address(0); //如果feeTo不等于零地址就是true，相反则是false
        uint _kLast = kLast; //定义K值
        if (feeOn) { //如果feeOn等于true
            if (_kLast != 0) { //如果K值不等于0
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1)); //计算_reserve0 * _reserve1的平方根
                uint rootKLast = Math.sqrt(_kLast); //计算K的平方根
                if (rootK > rootKLast) { //如果K1值大于K2值3
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast)); //分子 = ERC20总量 * (rootK - rootKLast)
                    uint denominator = rootK.mul(5).add(rootKLast); //分母 = rootK * 5 + rootLast
                    uint liquidity = numerator / denominator; //流动性 = 分子 / 分母
                    if (liquidity > 0) _mint(feeTo, liquidity); //如果流动性大于0，则把流动性铸造给工厂合约的feeTo地址
                }
            }
        } else if (_kLast != 0) { //否则如果_KLast不等于0
            kLast = 0; //那么k值就等于0
        }
    }

    //铸造流动性代币给to地址
    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();  //获取储备量
        uint balance0 = IERC20(token0).balanceOf(address(this)); //获取当前合约在token0合约内的余额
        uint balance1 = IERC20(token1).balanceOf(address(this)); //获取当前合约在token1合约内的余额
        uint amount0 = balance0.sub(_reserve0); //余额0减储备0
        uint amount1 = balance1.sub(_reserve1);//余额1减储备1

        bool feeOn = _mintFee(_reserve0, _reserve1); //返回铸造费开关
        uint _totalSupply = totalSupply; //获取totalSupply，必须在此处定义，因为totalSupply可以在mintFee中更新
                if (_totalSupply == 0) { //如果totalSupply等于0
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);//流动性 = （数量0 * 数量1）的平方根 - 最小流动性1000
           _mint(address(0), MINIMUM_LIQUIDITY); //在总量为0的初始状态永久锁定最低流动性
        } else {
            //流动性 = 最小值(amount0 * _totalSupply / _reserve0) 和 (amount1 * _totalSupply / _reserve1)
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED'); //确认流动性大于0
        _mint(to, liquidity); //将流动性铸造给to地址

        _update(balance0, balance1, _reserve0, _reserve1); //更新储备量
        if (feeOn) kLast = uint(reserve0).mul(reserve1); //如果铸造费开关为true，那么k值 = 储备量0 * 储备量1
        emit Mint(msg.sender, amount0, amount1); //触发铸造事件
    }

    // 销毁方法
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // 获取储备量0和储备量1
        address _token0 = token0;                                // 给token0赋值（节省gas）
        address _token1 = token1;                                // 给token1赋值（节省gas）
        uint balance0 = IERC20(_token0).balanceOf(address(this));//获取当前合约在token0合约中的余额
        uint balance1 = IERC20(_token1).balanceOf(address(this));//获取当前合约在token1合约中的余额
        uint liquidity = balanceOf[address(this)]; //从映射中获取当前合约的流动性数量

        bool feeOn = _mintFee(_reserve0, _reserve1); //返回铸造费开关
        uint _totalSupply = totalSupply; //获取totalSupply，必须在此处定义，因为totalSupply可以在mintFee中更新
        amount0 = liquidity.mul(balance0) / _totalSupply; //amount0 = 流动性数量 * 余额0 / totalSupply 使用余额确保按比例分配
        amount1 = liquidity.mul(balance1) / _totalSupply; //amount1 = 流动性数量 * 余额1 / totalSupply 使用余额确保按比例分配
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED'); //确认amount0和amount1都大于0
        _burn(address(this), liquidity); //销毁当前合约内的流动性数量
        _safeTransfer(_token0, to, amount0); //将amount0数量的_token0发送给to地址
        _safeTransfer(_token1, to, amount1); //将amount1数量的_token1发送给to地址
        balance0 = IERC20(_token0).balanceOf(address(this)); //更新balance0
        balance1 = IERC20(_token1).balanceOf(address(this)); //更新balance1

        _update(balance0, balance1, _reserve0, _reserve1); //更新储备量
        if (feeOn) kLast = uint(reserve0).mul(reserve1); //如果铸造费开关为true，k值 = 储备0 * 储备1
        emit Burn(msg.sender, amount0, amount1, to); //触发销毁事件
    }

    // 交换方法
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT'); //确认amount0Out或者amount1Out大于0
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); //获取储备量
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY'); //确认输出数量0，1 小于 reserve 0，1

        uint balance0; //初始化变量0
        uint balance1; //初始化变量1
        { //函数内部的花括号是标记作用域，防止堆栈过深导致gas超额
        address _token0 = token0; //给状态变量赋值0
        address _token1 = token1; //给状态变量赋值1
        require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO'); //to地址不等于_token0与_token1
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); //如果输出数量0大于零，就用安全数学发送输出数量0的_token0到to地址
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); //如果输出数量1大于零，就用安全数学发送输出数量1的_token1到to地址
        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data); //如果data的长度大于0就调用to地址接口
        balance0 = IERC20(_token0).balanceOf(address(this)); //余额0 = 当前合约在token0内的余额
        balance1 = IERC20(_token1).balanceOf(address(this)); //余额1 = 当前合约在token1内的余额
        }
        //如果余额0 > 储备0 - amount0Out 则 amount0In = 余额0 - (储备0 - amount0Out) 否则amount0In = 0
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        //如果余额1 > 储备1 - amount1Out 则 amount1In = 余额1 - (储备1 - amount1Out) 否则amount1In = 0
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT'); //确认输入0或者输入1必须有一个大于0
        { //又一个函数内部的花括号标记作用域，防止堆栈过深导致gas超额
        uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3)); //调整后的余额0 = 余额0 * 1000 - (amount0In * 3)
        uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3)); //调整后的余额1 = 余额1 * 1000 - (amount0In * 3)
        //确认balance0Adjusted * balance1Adjusted >= 储备0 * 储备1 * 1000000
        require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UniswapV2: K');
        }

        _update(balance0, balance1, _reserve0, _reserve1); //更新储备量
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to); //触发交换事件
    }

    //强制平衡以匹配储备
    function skim(address to) external lock {
        address _token0 = token0; // 给token0赋值（节省gas）
        address _token1 = token1; // 给token0赋值（节省gas）
        //将当前合约在_token0的余额减去储备量0，安全发送给to地址
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        //将当前合约在_token1的余额减去储备量1，安全发送给to地址
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    //强制准备金与余额匹配
    function sync() external lock {
        //按照余额匹配储备量
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}
