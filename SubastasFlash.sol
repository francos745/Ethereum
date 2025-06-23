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
    

    //Inicializa el contrato con una duración dada.
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

    //Verifica que se haya enviado ETH, suma el nuevo depósito al total del usuario, verifica que la oferta supere en al menos 5% a la mejor actual, registra la nueva oferta en historialOfertas, extiende el tiempo si quedan menos de 10 minutos.
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


    //finaliza la subasta solo si es el propietario
    function finalizar() external soloOwner {
        require(!finalizada, "Ya finalizo");
        require(block.timestamp >= inicio + duracion, "Aun no termina");

        finalizada = true;
        emit SubastaFinalizada(mejorOferente, mejorOferta);
    }

    //Solo válido si la subasta terminó, los no ganadores pueden retirar su depósito menos una comisión del 2%.
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

    //Permite al propietario retirar los fondos acumulados del ganador.
    function retirarFondos() external soloOwner {
        require(finalizada, "Subasta no finalizada");
        require(address(this).balance > 0, "Sin balance disponible");

        uint monto = address(this).balance;
        (bool exito, ) = payable(owner).call{value: monto}("");
        require(exito, "Fallo al transferir al owner");

        emit FondosRetirados(owner, monto);
    }

    //Calcula cuántos segundos faltan para que la subasta termine.
    function tiempoRestante() external view returns (uint) {
        if (block.timestamp >= inicio + duracion || finalizada) {
            return 0;
        } else {
            return (inicio + duracion) - block.timestamp;
        }
    }

    //muestra el balance del contrato
    function verBalance() external view returns (uint) {
        return address(this).balance;
    }

    //muestra el ganador de la subasta
    function mostrarGanador() external view returns (address, uint) {
        return (mejorOferente, mejorOferta);
    }

    //muestra todo el historial de ofertas por usuario
    function mostrarOfertas(address _oferente) external view returns (Oferta[] memory) {
        return historialOfertas[_oferente];
    }

    //Permite al usuario recuperar su oferta anterior, útil si hizo múltiples ofertas y no quiere dejar todo su capital ahí.
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

    //Obtener lista de oferentes
    function obtenerOferentes() external view returns (address[] memory) {
        return oferentes;
    }
}
