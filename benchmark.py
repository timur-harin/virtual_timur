from statistics import mean

import subprocess
import typing as t


GENERAL_STATS_LABELS = ["total time, s", "total # of events"]
LATENCY_STATS_LABELS = [
    "latency min",
    "latency avg",
    "latency max",
    "latency 95p",
    "latency sum",
]
THREADS_FAIRNESS_LABELS = [
    "events avg",
    "events stddev",
    "exec time avg",
    "exec time sttdev",
]

COMMON_LABELS = GENERAL_STATS_LABELS + LATENCY_STATS_LABELS + THREADS_FAIRNESS_LABELS
FILEIO_LABELS = [
    "ops reads/s",
    "ops writes/s",
    "ops fsyncs/s",
    "throughput read, MiB/s",
    "throughput write, MiB/s",
]


ParseFunc = t.Callable[[t.Iterator[str]], list[str]]


class Table:
    def __init__(self, cols: list[str]) -> None:
        self._matrix = []
        self._cols = cols

    def __setitem__(self, i: int, row: list[float]) -> float:
        self._matrix[i] = row

    def append(self, row: list[float]) -> None:
        self._matrix.append(row)

    def _get_avg(self) -> list[str]:
        columns = [
            [self._matrix[j][i] for j in range(len(self._matrix))]
            for i in range(len(self._cols))
        ]

        return ["{:.4f}".format(mean(x)) for x in columns]

    def __str__(self) -> str:
        header = " | ".join(["   "] + self._cols)
        separator = " | ".join(["---"] + ["-" * len(x) for x in self._cols])

        rows = [
            " | ".join([str(i + 1)] + [str(x) for x in r])
            for i, r in enumerate(self._matrix)
        ]

        avg = " | ".join(["Avg"] + self._get_avg())

        table = [header, separator] + rows + [avg]
        return "\n".join([f"| {x} |" for x in table])


def next_line(iterator: t.Iterator[str]) -> list[str]:
    line = next(iterator).strip().split()
    print(line)
    return line


def parse_float(iterator: t.Iterator[str], i: int = 1) -> float:
    return float(next_line(iterator)[i])


def parse_sec(iterator: t.Iterator[str], i: int = 2) -> float:
    return float(next_line(iterator)[i][:-1])


def parse_avg_stddev(iterator: t.Iterator[str], i: int = 2) -> list[float]:
    return [float(x) for x in next_line(iterator)[i].split("/")]


def parse_general_stats(iterator: t.Iterator[str]) -> list[float]:
    next(iterator)
    return [parse_sec(iterator), parse_float(iterator, i=4)]


def parse_latency_ms(iterator: t.Iterator[str]) -> list[float]:
    next(iterator)

    res = [parse_float(iterator) for _ in range(3)]
    res.append(parse_float(iterator, i=2))
    res.append(parse_float(iterator))

    return res


def parse_threads_fairness(iterator: t.Iterator[str]) -> list[float]:
    next(iterator)
    events = parse_avg_stddev(iterator)
    exec_time = parse_avg_stddev(iterator, i=3)
    return list(events) + list(exec_time)


def parse_cpu_eps(iterator: t.Iterator[str]) -> list[float]:
    next(iterator)
    return [parse_float(iterator, i=3)]


def parse_ops_mem_speed(iterator: t.Iterator[str]) -> list[float]:
    ops_per_sec = float(next_line(iterator)[3][1:])
    mem_speed = float(next_line(iterator)[3][1:])
    return [ops_per_sec, mem_speed]


def parse_file_ops(iterator: t.Iterator[str]) -> list[float]:
    next(iterator)
    return [parse_float(iterator) for _ in range(3)]


def parse_throughput(iterator: t.Iterator[str]) -> list[float]:
    next(iterator)
    return [parse_float(iterator, i=2), parse_float(iterator, i=2)]


def skip_header(iterator: t.Iterator[str], n: int = 6) -> None:
    for _ in range(n):
        next(iterator)


def sysbench_output_iter(cmd: str) -> t.Iterator[str]:
    p = subprocess.Popen(cmd.split(), stdout=subprocess.PIPE)
    out, _ = p.communicate()
    return iter([x.strip() for x in out.decode().split("\n") if x.strip()])


def test_primes(iterator: t.Iterator[str]) -> list[float]:
    skip_header(iterator, n=7)
    res = parse_cpu_eps(iterator)
    res += parse_general_stats(iterator)
    res += parse_latency_ms(iterator)
    res += parse_threads_fairness(iterator)
    return res


def test_threads(iterator: t.Iterator[str]) -> list[float]:
    skip_header(iterator, n=6)
    res = parse_general_stats(iterator)
    res += parse_latency_ms(iterator)
    res += parse_threads_fairness(iterator)
    return res


def test_memory(iterator: t.Iterator[str]) -> list[float]:
    skip_header(iterator, n=11)
    res = parse_ops_mem_speed(iterator)
    res += parse_general_stats(iterator)
    res += parse_latency_ms(iterator)
    res += parse_threads_fairness(iterator)
    return res


def test_fileio(iterator: t.Iterator[str]) -> list[float]:
    skip_header(iterator, n=16)
    res = parse_file_ops(iterator)
    res += parse_throughput(iterator)
    res += parse_general_stats(iterator)
    res += parse_latency_ms(iterator)
    res += parse_threads_fairness(iterator)
    return res


def benchmark(func: ParseFunc, cmd: str, cols: list[str], n: int = 10) -> Table:
    table = Table(cols)

    for _ in range(n):
        iterator = sysbench_output_iter(cmd)
        table.append(func(iterator))

    return table


if __name__ == "__main__":
    lines = []

    cmd_cpu = "sysbench cpu --threads=100 --time=60 --cpu-max-prime=64000 run"
    table_cpu = benchmark(test_primes, cmd_cpu, ["CPU events/s"] + COMMON_LABELS)

    lines.append(f"`{cmd_cpu}`")
    lines.append(str(table_cpu))

    cmd_threads = (
        "sysbench threads --threads=64 --thread-yields=100 --thread-locks=2 run"
    )
    table_threads = benchmark(test_threads, cmd_threads, COMMON_LABELS)

    lines.append(f"`{cmd_threads}`")
    lines.append(str(table_threads))

    cmd_random_memory = (
        "sysbench memory --threads=100 --time=60 --memory-oper=write run"
    )
    table_random_memory = benchmark(
        test_memory,
        cmd_random_memory,
        ["Ops/s", "Mem spped, MiB/s"] + COMMON_LABELS,
    )

    lines.append(f"`{cmd_random_memory}`")
    lines.append(str(table_random_memory))

    cmd_memory_speed = (
        "sysbench memory --memory-block-size=1M --memory-total-size=10G run"
    )
    table_memory_speed = benchmark(
        test_memory,
        cmd_memory_speed,
        ["Ops/s", "Mem spped, MiB/s"] + COMMON_LABELS,
    )

    lines.append(f"`{cmd_memory_speed}`")
    lines.append(str(table_memory_speed))

    sysbench_output_iter("sysbench fileio --file-total-size=10G prepare")

    cmd_fileio = "sysbench fileio --file-total-size=10G --file-test-mode=rndrw --time=120 --time=300 --max-requests=0 run"

    table_fileio = benchmark(test_fileio, cmd_fileio, FILEIO_LABELS + COMMON_LABELS)

    lines.append(f"`{cmd_fileio}`")
    lines.append(str(table_fileio))

    sysbench_output_iter("sysbench fileio --file-total-size=10G cleanup")

    with open("report.md", "w") as file:
        file.write("\n\n".join(lines))