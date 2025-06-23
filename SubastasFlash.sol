// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
/**
 * @title SubastaFlash
 * @dev Smart contract de una subasta tipo "puja creciente" con extensión automática y reembolsos parciales.
 */
contract SubastaFlash {
    address public owner;
    address public mejorOferente;
    uint public mejorOferta;

    uint public inicio;
    uint public duracion;
    uint constant EXTENSION_TIEMPO = 10 minutes;
    bool public finalizada;

    struct Oferta {
        uint monto;
        uint timestamp;
    }

    mapping(address => uint) public depositos;
    mapping(address => Oferta[]) public historialOfertas;
    address[] public oferentes;

    event NuevaOferta(address indexed oferente, uint monto);
    event SubastaFinalizada(address ganador, uint monto);
    event FondosRetirados(address indexed to, uint amount);
    event ReembolsoParcial(address indexed oferente, uint monto);

    constructor(uint _duracion) {
        owner = msg.sender;
        inicio = block.timestamp;
        duracion = _duracion;
    }
    modifier subastaActiva() {
        require(!finalizada, "Subasta finalizada");
        require(block.timestamp <= inicio + duracion, "Tiempo terminado");
        _;
    }

    modifier soloOwner() {
        require(msg.sender == owner, "No eres el owner");
        _;
    }

    function ofertar() external payable subastaActiva {
        require(msg.value > 0, "Debes enviar ETH");

        uint total = depositos[msg.sender] + msg.value;
        uint minimoRequerido = mejorOferta + (mejorOferta * 5) / 100;

        require(total >= minimoRequerido, "La oferta debe superar en al menos 5%");

        if (depositos[msg.sender] == 0) {
            oferentes.push(msg.sender);
        }

        depositos[msg.sender] = total;
        historialOfertas[msg.sender].push(Oferta(total, block.timestamp));

        mejorOferente = msg.sender;
        mejorOferta = total;

        if ((inicio + duracion - block.timestamp) <= EXTENSION_TIEMPO) {
            duracion += EXTENSION_TIEMPO;
        }

        emit NuevaOferta(msg.sender, total);
    }

    function finalizar() external soloOwner {
        require(!finalizada, "Ya finalizo");
        require(block.timestamp >= inicio + duracion, "Aun no termina");

        finalizada = true;
        emit SubastaFinalizada(mejorOferente, mejorOferta);
    }

    function retirar() external {
        require(finalizada, "Subasta no finalizada");
        require(msg.sender != mejorOferente, "Ganador no puede retirar");

        uint deposito = depositos[msg.sender];
        require(deposito > 0, "Nada para retirar");

        uint comision = (deposito * 2) / 100;
        uint reembolso = deposito - comision;

        depositos[msg.sender] = 0;
        payable(msg.sender).transfer(reembolso);
    }

    function retirarFondos() external soloOwner {
        require(finalizada, "Subasta no finalizada");
        require(address(this).balance > 0, "Sin balance disponible");

        uint monto = address(this).balance;
        (bool exito, ) = payable(owner).call{value: monto}("");
        require(exito, "Fallo al transferir al owner");

        emit FondosRetirados(owner, monto);
    }

    function tiempoRestante() external view returns (uint) {
        if (block.timestamp >= inicio + duracion || finalizada) {
            return 0;
        } else {
            return (inicio + duracion) - block.timestamp;
        }
    }

    function verBalance() external view returns (uint) {
        return address(this).balance;
    }

    function mostrarGanador() external view returns (address, uint) {
        return (mejorOferente, mejorOferta);
    }

    function mostrarOfertas(address _oferente) external view returns (Oferta[] memory) {
        return historialOfertas[_oferente];
    }

    function reembolsoParcial() external subastaActiva {
        Oferta[] storage ofertas = historialOfertas[msg.sender];
        require(ofertas.length >= 2, "No hay ofertas anteriores");

        uint montoReembolsable = ofertas[ofertas.length - 2].monto;
        require(montoReembolsable > 0, "Nada que reembolsar");

        depositos[msg.sender] -= montoReembolsable;
        ofertas[ofertas.length - 2].monto = 0;

        payable(msg.sender).transfer(montoReembolsable);
        emit ReembolsoParcial(msg.sender, montoReembolsable);
    }

    function obtenerOferentes() external view returns (address[] memory) {
        return oferentes;
    }
}
