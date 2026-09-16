-- Number/time formatting shared by the client HUD and the server-rendered
-- world leaderboards. It lives in Shared rather than in the client Theme
-- because both sides now display Cash values, and two implementations of
-- "how do we write 1,240,000" would drift apart the first time one is tuned.

local Format = {}

-- A escada de sufixos, e ela precisa chegar ONDE A ECONOMIA CHEGA.
--
-- A versão anterior parava em "T". O vigésimo quinto mundo custa 1,13x10^15 e o
-- endgame passa disso com folga, então tudo acima de mil trilhões era impresso
-- como o número inteiro com um T colado no fim: "2464.51T", e em casos piores
-- "712965291770724634624.00T". Isso não é um número feio — é um componente
-- quebrado, porque nenhuma pílula de largura fixa comporta vinte e um dígitos.
--
-- Vai até Dc (10^33), muito além de qualquer valor que a curva produz. O custo
-- de uma tabela maior é zero e o custo de ela ser curta demais é o defeito
-- acima, então o dimensionamento é deliberadamente generoso.
local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- Abbreviates large values the way this genre does (1.2K, 3.4M). Players read
-- a raw 7-digit number as noise, and it overflows every fixed-width pill on a
-- phone. Below 1K the exact number still means something to a new player
-- counting their first few hundred Cash.
--
-- REGRA DAS CASAS DECIMAIS: uma casa enquanto a mantissa tem dois dígitos,
-- nenhuma a partir de três.
--
--   1.2K   45.6K   123K   2.4M   1.2B   15.7T
--
-- Isso mantém o texto entre quatro e seis caracteres SEMPRE, que é a
-- propriedade que importa: a largura do componente pode ser decidida uma vez e
-- nunca ser estourada. Casas decimais fixas não dariam isso — "123.45K" é 40%
-- mais largo que "1.23K", e a diferença aparece como texto cortado justamente
-- quando o jogador ficou rico.
function Format.Abbreviate(value: number): string
	local absolute = math.abs(value)

	-- Abaixo de mil, o número exato. É a faixa da primeira meia hora de jogo, e
	-- ali "437" diz mais do que "0.4K".
	if absolute < 1000 then
		return tostring(math.floor(value))
	end

	-- NaN e infinito nunca deveriam chegar aqui, mas se chegarem o laço abaixo
	-- não termina. Uma HUD congelada é pior que uma HUD com "?" nela.
	if value ~= value or absolute == math.huge then
		return "?"
	end

	local scaled = absolute
	local index = 0

	while scaled >= 1000 and index < #SUFFIXES do
		scaled /= 1000
		index += 1
	end

	local sign = if value < 0 then "-" else ""
	local suffix = SUFFIXES[index]

	-- Arredondar pode empurrar 999.95 para 1000.0, que imprimiria "1000.0K" em
	-- vez de "1M". Verificado depois do arredondamento, não antes.
	local rounded = if scaled < 100 then math.floor(scaled * 10 + 0.5) / 10 else math.floor(scaled + 0.5)
	if rounded >= 1000 and index < #SUFFIXES then
		rounded /= 1000
		suffix = SUFFIXES[index + 1]
	end

	if rounded < 100 then
		return `{sign}{string.format("%.1f", rounded)}{suffix}`
	end
	return `{sign}{string.format("%d", rounded)}{suffix}`
end

-- O mesmo número com o cifrão na frente, para tudo que é Cash.
--
-- Existe para que "é dinheiro" seja uma decisão tomada em UM lugar. Estava
-- espalhado como concatenação manual em cada rótulo, que é como metade da HUD
-- acabou mostrando o símbolo e a outra metade não.
function Format.Cash(value: number): string
	return `$` .. Format.Abbreviate(value)
end

function Format.Duration(seconds: number): string
	local clamped = math.max(math.floor(seconds), 0)
	return string.format("%d:%02d", clamped // 60, clamped % 60)
end

-- "3 / 615" para a mochila e para qualquer progresso contado.
--
-- Os dois lados abreviados pela mesma regra: a capacidade passa de mil com as
-- melhorias de mochila, e um "12 / 1215" empurrava o componente para fora do
-- lugar exatamente como o Cash fazia.
function Format.Fraction(current: number, maximum: number): string
	return `{Format.Abbreviate(current)} / {Format.Abbreviate(maximum)}`
end

return Format
