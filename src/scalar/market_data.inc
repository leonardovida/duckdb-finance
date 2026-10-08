//===--------------------------------------------------------------------===//
// Price transforms and quote/trade microstructure scalars
//===--------------------------------------------------------------------===//
// Each kernel is a compile-time operation over N DOUBLE inputs: no per-row
// strings or exceptions. A NULL input, a non-finite result or a domain case
// the kernel rejects (crossed quotes, negative sizes, empty books) gives NULL.
template <class OP, idx_t N>
static void MarketScalarFunction(DataChunk &args, ExpressionState &, Vector &result) {
	const auto count = args.size();
	const bool constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	auto output = GetResultData<double>(result, constant);
	UnifiedVectorFormat formats[N];
	const double *data[N];
	bool all_valid = true;
	for (idx_t c = 0; c < N; c++) {
		FinanceToUnifiedFormat(args.data[c], count, formats[c]);
		data[c] = UnifiedVectorFormat::GetData<double>(formats[c]);
		all_valid = all_valid && formats[c].validity.AllValid();
	}
	const idx_t rows = constant && count > 0 ? idx_t(1) : count;
	double in[N];
	for (idx_t row = 0; row < rows; row++) {
		bool valid = true;
		for (idx_t c = 0; c < N; c++) {
			auto index = formats[c].sel->get_index(row);
			if (!all_valid && !formats[c].validity.RowIsValid(index)) {
				valid = false;
				break;
			}
			in[c] = data[c][index];
		}
		double value;
		if (valid && OP::Compute(in, value) && std::isfinite(value)) {
			output[row] = value;
		} else {
			SetResultNull(result, row, count, constant);
		}
	}
}

// TA-Lib AVGPRICE (open, high, low, close).
struct AvgPriceOp {
	static bool Compute(const double *in, double &out) {
		out = (in[0] + in[1] + in[2] + in[3]) / 4.0;
		return true;
	}
};

// TA-Lib TYPPRICE (high, low, close).
struct TypPriceOp {
	static bool Compute(const double *in, double &out) {
		out = (in[0] + in[1] + in[2]) / 3.0;
		return true;
	}
};

// TA-Lib MEDPRICE (high, low).
struct MedianPriceOp {
	static bool Compute(const double *in, double &out) {
		out = (in[0] + in[1]) / 2.0;
		return true;
	}
};

// TA-Lib WCLPRICE (high, low, close).
struct WeightedCloseOp {
	static bool Compute(const double *in, double &out) {
		out = (in[0] + in[1] + 2.0 * in[2]) / 4.0;
		return true;
	}
};

// TA-Lib BOP (open, high, low, close): (close - open) / (high - low), 0 when
// high <= low.
struct BalanceOfPowerOp {
	static bool Compute(const double *in, double &out) {
		auto range = in[1] - in[2];
		out = range > 0.0 ? (in[3] - in[0]) / range : 0.0;
		return std::isfinite(in[0]) && std::isfinite(in[3]) && std::isfinite(range);
	}
};

// Quotes (bid, ask): crossed books (bid > ask) are invalid; locked books are not.
static bool ValidQuotes(double bid, double ask) {
	return std::isfinite(bid) && std::isfinite(ask) && bid <= ask;
}

struct MidOp {
	static bool Compute(const double *in, double &out) {
		out = (in[0] + in[1]) / 2.0;
		return ValidQuotes(in[0], in[1]);
	}
};

struct SpreadOp {
	static bool Compute(const double *in, double &out) {
		out = in[1] - in[0];
		return ValidQuotes(in[0], in[1]);
	}
};

// Quoted spread in basis points of the mid; NULL unless the mid is positive.
struct SpreadBpsOp {
	static bool Compute(const double *in, double &out) {
		auto mid = (in[0] + in[1]) / 2.0;
		out = (in[1] - in[0]) / mid * 10000.0;
		return ValidQuotes(in[0], in[1]) && mid > 0.0;
	}
};

static bool ValidSizes(double bid_size, double ask_size) {
	return bid_size >= 0.0 && ask_size >= 0.0 && bid_size + ask_size > 0.0;
}

// Size-weighted mid (bid, bid_size, ask, ask_size):
// (bid * ask_size + ask * bid_size) / (bid_size + ask_size).
struct MicropriceOp {
	static bool Compute(const double *in, double &out) {
		if (!ValidQuotes(in[0], in[2]) || !ValidSizes(in[1], in[3])) {
			return false;
		}
		out = (in[0] * in[3] + in[2] * in[1]) / (in[1] + in[3]);
		return true;
	}
};

// (bid_size - ask_size) / (bid_size + ask_size) in [-1, 1].
struct ImbalanceOp {
	static bool Compute(const double *in, double &out) {
		if (!ValidSizes(in[0], in[1])) {
			return false;
		}
		out = (in[0] - in[1]) / (in[0] + in[1]);
		return true;
	}
};

enum class TradeSignRule : uint8_t { LEE_READY, EMO };

static TradeSignRule ParseTradeSignRule(const string &text) {
	auto lower = StringUtil::Lower(text);
	if (lower == "lee_ready" || lower == "lee-ready") {
		return TradeSignRule::LEE_READY;
	}
	if (lower == "emo") {
		return TradeSignRule::EMO;
	}
	throw InvalidInputException("fin_trade_sign: unknown method '%s' (expected 'lee_ready' or 'emo')", text);
}

// Trade classification: +1 buyer-initiated, -1 seller-initiated, 0 unclassified.
// Lee and Ready (1991): above the quote midpoint +1, below -1; at the midpoint
// the tick test against the previous trade price. EMO (Ellis, Michaely and
// O'Hara 2000): at or above the ask +1, at or below the bid -1, otherwise the
// tick test. A NULL previous price leaves the tick test unclassified (0).
// Crossed quotes or non-finite inputs give NULL.
static void TradeSignFunction(DataChunk &args, ExpressionState &, Vector &result) {
	const auto count = args.size();
	const bool constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	auto output = GetResultData<double>(result, constant);
	auto rule = TradeSignRule::LEE_READY;
	if (args.ColumnCount() >= 5) {
		auto &method = args.data[4];
		if (method.GetVectorType() != VectorType::CONSTANT_VECTOR || ConstantVector::IsNull(method)) {
			throw InvalidInputException("fin_trade_sign: method must be a non-NULL constant");
		}
		rule = ParseTradeSignRule(ConstantVector::GetData<string_t>(method)[0].GetString());
	}
	const idx_t inputs = std::min<idx_t>(args.ColumnCount(), 4);
	UnifiedVectorFormat formats[4];
	const double *data[4];
	for (idx_t c = 0; c < inputs; c++) {
		FinanceToUnifiedFormat(args.data[c], count, formats[c]);
		data[c] = UnifiedVectorFormat::GetData<double>(formats[c]);
	}
	const idx_t rows = constant && count > 0 ? idx_t(1) : count;
	for (idx_t row = 0; row < rows; row++) {
		double in[3];
		bool valid = true;
		for (idx_t c = 0; c < 3 && valid; c++) {
			auto index = formats[c].sel->get_index(row);
			valid = formats[c].validity.RowIsValid(index);
			in[c] = data[c][index];
		}
		if (!valid || !std::isfinite(in[0]) || !ValidQuotes(in[1], in[2])) {
			SetResultNull(result, row, count, constant);
			continue;
		}
		auto price = in[0];
		double sign = 0.0;
		bool decided = false;
		if (rule == TradeSignRule::LEE_READY) {
			auto mid = (in[1] + in[2]) / 2.0;
			if (price != mid) {
				sign = price > mid ? 1.0 : -1.0;
				decided = true;
			}
		} else if (price >= in[2] || price <= in[1]) {
			sign = price >= in[2] ? 1.0 : -1.0;
			decided = true;
		}
		if (!decided && inputs >= 4) {
			auto index = formats[3].sel->get_index(row);
			if (formats[3].validity.RowIsValid(index)) {
				auto previous = data[3][index];
				if (!std::isfinite(previous)) {
					SetResultNull(result, row, count, constant);
					continue;
				}
				sign = price > previous ? 1.0 : (price < previous ? -1.0 : 0.0);
			}
		}
		output[row] = sign;
	}
}

static unique_ptr<FunctionData> BindTradeSign(ClientContext &context, ScalarFunction &bound_function,
                                              vector<unique_ptr<Expression>> &arguments) {
	RejectNamedScalarArguments(bound_function, arguments);
	if (arguments.size() >= 5) {
		auto &method = *arguments[4];
		if (!method.IsFoldable()) {
			throw InvalidInputException("fin_trade_sign: method must be a constant");
		}
		auto value = ExpressionExecutor::EvaluateScalar(context, method, true);
		if (value.IsNull()) {
			throw InvalidInputException("fin_trade_sign: method must be a non-NULL constant");
		}
		ParseTradeSignRule(StringValue::Get(value.DefaultCastAs(LogicalType::VARCHAR)));
	}
	return nullptr;
}

enum class ListOp : uint8_t { SUM, MEAN, INVERSE_VOL, NORMALIZE, SCALE };

static void ListScalarFunction(DataChunk &args, ExpressionState &, Vector &result, ListOp op) {
	auto count = args.size();
	auto constant = AllInputsConstant(args);
	auto row_count = constant && count > 0 ? idx_t(1) : count;
	PreparedInputs input(args);
	DoubleListArg list(args, input, 0);
	const double *values = list.values;
	if (op == ListOp::SUM || op == ListOp::MEAN) {
		ExecuteDouble(args, result, [&](const PreparedInputs &in, idx_t row) {
			auto entry = list.Entry(in, row);
			if (entry.length == 0 || list.HasNullElement(entry)) {
				return FIN_NAN;
			}
			double sum = CompensatedSum(values + entry.offset, entry.length);
			return op == ListOp::SUM ? sum : sum / double(entry.length);
		});
		return;
	}
	ListResultWriter writer(result, constant);
	for (idx_t row = 0; row < row_count; row++) {
		if (input.HasNull(row)) {
			writer.SetNull(row, count);
			continue;
		}
		auto entry = list.Entry(input, row);
		if (list.HasNullElement(entry)) {
			writer.SetNull(row, count);
			continue;
		}
		const double *x = values + entry.offset;
		auto n = entry.length;
		bool ok = true;
		double factor = 1.0;
		if (op == ListOp::SCALE) {
			factor = input.GetDouble(1, row);
			ok = IsFinite(factor);
		} else if (op == ListOp::NORMALIZE) {
			double sum = 0.0;
			for (idx_t i = 0; ok && i < n; i++) {
				ok = IsFinite(x[i]);
				sum += x[i];
			}
			ok = ok && IsFinite(sum) && sum != 0.0;
			factor = 1.0 / sum;
		} else {
			double sum = 0.0;
			for (idx_t i = 0; ok && i < n; i++) {
				ok = x[i] > 0.0 && IsFinite(x[i]);
				sum += 1.0 / x[i];
			}
			ok = ok && n > 0 && IsFinite(sum);
			factor = 1.0 / sum;
		}
		if (!ok) {
			writer.SetNull(row, count);
			continue;
		}
		auto out = writer.Begin(n);
		x = list.values + entry.offset;
		for (idx_t i = 0; ok && i < n; i++) {
			if (op == ListOp::NORMALIZE) {
				out[i] = x[i] * factor;
			} else if (op == ListOp::INVERSE_VOL) {
				out[i] = (1.0 / x[i]) * factor;
			} else {
				out[i] = x[i] * factor;
			}
			ok = IsFinite(out[i]);
		}
		if (!ok) {
			writer.SetNull(row, count);
			continue;
		}
		writer.Commit(row, n);
	}
	writer.Finish();
}

enum class BinaryListOp : uint8_t { DOT, TURNOVER, ADD, SUB, MULTIPLY };

static void BinaryListFunction(DataChunk &args, ExpressionState &, Vector &result, BinaryListOp op) {
	auto count = args.size();
	auto constant = AllInputsConstant(args);
	auto row_count = constant && count > 0 ? idx_t(1) : count;
	PreparedInputs input(args);
	DoubleListArg left(args, input, 0);
	DoubleListArg right(args, input, 1);
	if (op == BinaryListOp::DOT || op == BinaryListOp::TURNOVER) {
		ExecuteDouble(args, result, [&](const PreparedInputs &in, idx_t row) {
			auto l = left.Entry(in, row);
			auto r = right.Entry(in, row);
			if (l.length != r.length || l.length == 0 || left.HasNullElement(l) || right.HasNullElement(r)) {
				return FIN_NAN;
			}
			const double *x = left.values + l.offset;
			const double *y = right.values + r.offset;
			if (op == BinaryListOp::DOT) {
				return CompensatedDot(x, y, l.length);
			}
			double turnover = 0.0;
			for (idx_t i = 0; i < l.length; i++) {
				turnover += std::fabs(y[i] - x[i]);
			}
			return 0.5 * turnover;
		});
		return;
	}
	ListResultWriter writer(result, constant);
	for (idx_t row = 0; row < row_count; row++) {
		if (input.IsNull(0, row) || input.IsNull(1, row)) {
			writer.SetNull(row, count);
			continue;
		}
		auto l = left.Entry(input, row);
		auto r = right.Entry(input, row);
		if (l.length != r.length || left.HasNullElement(l) || right.HasNullElement(r)) {
			writer.SetNull(row, count);
			continue;
		}
		auto out = writer.Begin(l.length);
		const double *x = left.values + l.offset;
		const double *y = right.values + r.offset;
		bool ok = true;
		for (idx_t i = 0; i < l.length; i++) {
			out[i] = op == BinaryListOp::ADD ? x[i] + y[i] : op == BinaryListOp::MULTIPLY ? x[i] * y[i] : x[i] - y[i];
			ok = ok && IsFinite(out[i]);
		}
		if (!ok) {
			writer.SetNull(row, count);
			continue;
		}
		writer.Commit(row, l.length);
	}
	writer.Finish();
}

static void EqualWeightsFunction(DataChunk &args, ExpressionState &, Vector &result) {
	auto constant = AllInputsConstant(args);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	PreparedInputs input(args);
	ListResultWriter writer(result, constant);
	for (idx_t row = 0; row < row_count; row++) {
		if (input.IsNull(0, row)) {
			writer.SetNull(row, args.size());
			continue;
		}
		auto n = input.GetInteger(0, row);
		if (n <= 0 || n > 100000000) {
			writer.SetNull(row, args.size());
			continue;
		}
		auto out = writer.Begin(idx_t(n));
		for (int64_t i = 0; i < n; i++) {
			out[i] = 1.0 / double(n);
		}
		writer.Commit(row, idx_t(n));
	}
	writer.Finish();
}

enum class PortfolioOp : uint8_t { VARIANCE, VOL };

//! w' S w with compensated row sums. Returns NaN for shape mismatches, NULL elements, or empty inputs.
static double PortfolioVariance(const DoubleListArg &weights, const list_entry_t &w_entry, const MatrixArg &matrix,
                                const list_entry_t &m_entry) {
	auto n = w_entry.length;
	if (n == 0 || m_entry.length != n || weights.HasNullElement(w_entry)) {
		return FIN_NAN;
	}
	const double *w = weights.values + w_entry.offset;
	double total = 0.0;
	double total_comp = 0.0;
	for (idx_t r = 0; r < n; r++) {
		if (matrix.row_validity->CanHaveNull() && !matrix.row_validity->RowIsValid(m_entry.offset + r)) {
			return FIN_NAN;
		}
		auto row_entry = matrix.rows[m_entry.offset + r];
		if (row_entry.length != n) {
			return FIN_NAN;
		}
		if (matrix.value_validity->CanHaveNull()) {
			for (idx_t c = 0; c < n; c++) {
				if (!matrix.value_validity->RowIsValid(row_entry.offset + c)) {
					return FIN_NAN;
				}
			}
		}
		double sigma = CompensatedDot(matrix.values + row_entry.offset, w, n);
		double prod = w[r] * sigma;
		double t = total + prod;
		double z = t - total;
		total_comp += (total - (t - z)) + (prod - z);
		total = t;
	}
	return total + total_comp;
}

static double PortfolioVolatility(double variance) {
	if (!IsFinite(variance) || variance < -1e-12) {
		return FIN_NAN;
	}
	return std::sqrt(std::max(0.0, variance));
}

static void PortfolioScalarFunction(DataChunk &args, ExpressionState &, Vector &result, PortfolioOp op) {
	PreparedInputs input(args);
	DoubleListArg weights(args, input, 0);
	MatrixArg matrix(args, input, 1);
	ExecuteDouble(args, result, [&](const PreparedInputs &in, idx_t row) {
		double var = PortfolioVariance(weights, weights.Entry(in, row), matrix, matrix.Entry(in, row));
		double vol = PortfolioVolatility(var);
		if (!IsFinite(vol)) {
			return FIN_NAN;
		}
		return op == PortfolioOp::VARIANCE ? var : vol;
	});
}

static void PortfolioSharpeFunction(DataChunk &args, ExpressionState &, Vector &result) {
	PreparedInputs input(args);
	DoubleListArg weights(args, input, 0);
	DoubleListArg mu(args, input, 1);
	MatrixArg matrix(args, input, 2);
	ExecuteDouble(args, result, [&](const PreparedInputs &in, idx_t row) {
		auto w_entry = weights.Entry(in, row);
		auto mu_entry = mu.Entry(in, row);
		if (mu_entry.length != w_entry.length || mu.HasNullElement(mu_entry)) {
			return FIN_NAN;
		}
		auto vol = PortfolioVolatility(PortfolioVariance(weights, w_entry, matrix, matrix.Entry(in, row)));
		if (!IsFinite(vol)) {
			return FIN_NAN;
		}
		double expected = CompensatedDot(weights.values + w_entry.offset, mu.values + mu_entry.offset, w_entry.length);
		double risk_free = args.ColumnCount() >= 4 ? in.GetDouble(3, row) : 0.0;
		return (expected - risk_free) / vol;
	});
}

static void MatrixShapeFunction(DataChunk &args, ExpressionState &, Vector &result) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	PreparedInputs input(args);
	MatrixArg matrix(args, input, 0);
	auto &children = StructVector::GetEntries(result);
	auto rows_out = FlatVector::GetDataMutable<int64_t>(FINANCE_STRUCT_CHILD(children[0]));
	auto cols_out = FlatVector::GetDataMutable<int64_t>(FINANCE_STRUCT_CHILD(children[1]));
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		idx_t n_rows, n_cols;
		if (input.IsNull(0, row) || !matrix.Shape(matrix.Entry(input, row), n_rows, n_cols)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		rows_out[row] = int64_t(n_rows);
		cols_out[row] = int64_t(n_cols);
	}
}

static void MatrixVecMulFunction(DataChunk &args, ExpressionState &, Vector &result) {
	PreparedInputs input(args);
	auto count = args.size();
	auto constant = AllInputsConstant(args);
	auto row_count = constant && count > 0 ? idx_t(1) : count;
	MatrixArg matrix(args, input, 0);
	DoubleListArg vec(args, input, 1);
	ListResultWriter writer(result, constant);
	vector<double> dense;
	for (idx_t row = 0; row < row_count; row++) {
		idx_t n_rows, n_cols;
		if (input.HasNull(row) || !matrix.Read(matrix.Entry(input, row), n_rows, n_cols, dense)) {
			writer.SetNull(row, count);
			continue;
		}
		auto v_entry = vec.Entry(input, row);
		if (vec.HasNullElement(v_entry) || (n_rows > 0 && v_entry.length != n_cols)) {
			writer.SetNull(row, count);
			continue;
		}
		auto out = writer.Begin(n_rows);
		bool ok = true;
		for (idx_t r = 0; r < n_rows; r++) {
			out[r] = CompensatedDot(dense.data() + r * n_cols, vec.values + v_entry.offset, n_cols);
			ok = ok && IsFinite(out[r]);
		}
		if (!ok) {
			writer.SetNull(row, count);
			continue;
		}
		writer.Commit(row, n_rows);
	}
	writer.Finish();
}

enum class MatrixOp : uint8_t { TRANSPOSE, CHOLESKY, NEAREST_PSD };

static void MatrixNestedFunction(DataChunk &args, ExpressionState &, Vector &result, MatrixOp op) {
	PreparedInputs input(args);
	auto count = args.size();
	auto constant = AllInputsConstant(args);
	auto row_count = constant && count > 0 ? idx_t(1) : count;
	MatrixArg matrix(args, input, 0);
	ConfigArg<PSDMethod> method(args, op == MatrixOp::NEAREST_PSD ? 1 : DConstants::INVALID_INDEX, ParsePSDMethod,
	                            PSDMethod::CLIP);
	MatrixResultWriter writer(result, constant);
	vector<double> dense;
	vector<double> out;
	for (idx_t row = 0; row < row_count; row++) {
		idx_t n_rows, n_cols;
		if (input.HasNull(row) || !matrix.Read(matrix.Entry(input, row), n_rows, n_cols, dense)) {
			writer.SetNull(row, count);
			continue;
		}
		bool ok = true;
		if (op == MatrixOp::TRANSPOSE) {
			out.resize(n_rows * n_cols);
			for (idx_t r = 0; r < n_rows; r++) {
				for (idx_t c = 0; c < n_cols; c++) {
					out[c * n_rows + r] = dense[r * n_cols + c];
				}
			}
			std::swap(n_rows, n_cols);
		} else if (n_rows == 0 || n_rows != n_cols) {
			ok = false;
		} else if (op == MatrixOp::CHOLESKY) {
			ok = MatrixCholesky(dense, n_rows, out);
		} else {
			ok = NearestPSD(dense, n_rows, method.Get(input, row));
			out = dense;
		}
		if (!ok || (op != MatrixOp::TRANSPOSE && !AllFinite(out))) {
			writer.SetNull(row, count);
			continue;
		}
		writer.Write(row, out.data(), n_rows, n_cols);
	}
	writer.Finish();
}

//! Dense product using an i-k-j loop over row-major buffers (cache friendly, no transposed copy).
static void MatrixMulFunction(DataChunk &args, ExpressionState &, Vector &result) {
	PreparedInputs input(args);
	auto count = args.size();
	auto constant = AllInputsConstant(args);
	auto row_count = constant && count > 0 ? idx_t(1) : count;
	MatrixArg left_arg(args, input, 0);
	MatrixArg right_arg(args, input, 1);
	MatrixResultWriter writer(result, constant);
	vector<double> left, right, out;
	for (idx_t row = 0; row < row_count; row++) {
		idx_t lr, lc, rr, rc;
		if (input.IsNull(0, row) || input.IsNull(1, row) || !left_arg.Read(left_arg.Entry(input, row), lr, lc, left) ||
		    !right_arg.Read(right_arg.Entry(input, row), rr, rc, right)) {
			writer.SetNull(row, count);
			continue;
		}
		if (lr == 0 || rr == 0) {
			writer.Write(row, nullptr, 0, 0);
			continue;
		}
		if (lc != rr) {
			writer.SetNull(row, count);
			continue;
		}
		out.assign(lr * rc, 0.0);
		constexpr idx_t BLOCK = 64;
		for (idx_t k0 = 0; k0 < lc; k0 += BLOCK) {
			idx_t k1 = std::min(lc, k0 + BLOCK);
			for (idx_t i = 0; i < lr; i++) {
				double *out_row = out.data() + i * rc;
				for (idx_t k = k0; k < k1; k++) {
					double a = left[i * lc + k];
					const double *right_row = right.data() + k * rc;
					for (idx_t j = 0; j < rc; j++) {
						out_row[j] += a * right_row[j];
					}
				}
			}
		}
		if (!AllFinite(out)) {
			writer.SetNull(row, count);
			continue;
		}
		writer.Write(row, out.data(), lr, rc);
	}
	writer.Finish();
}

static void MatrixIsPsdFunction(DataChunk &args, ExpressionState &, Vector &result) {
	PreparedInputs probe(args);
	MatrixArg matrix(args, probe, 0);
	vector<double> dense;
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		idx_t n_rows, n_cols;
		if (!matrix.Read(matrix.Entry(input, row), n_rows, n_cols, dense)) {
			return -1;
		}
		if (n_rows != n_cols) {
			return 0;
		}
		auto tolerance = args.ColumnCount() >= 2 ? input.GetDouble(1, row) : 1e-10;
		return MatrixIsPSD(dense, n_rows, tolerance);
	});
}

static void ValidateOhlcFunction(DataChunk &args, ExpressionState &, Vector &result) {
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	PreparedInputs input(args);
	auto &children = StructVector::GetEntries(result);
	auto &reason_vector = FINANCE_STRUCT_CHILD(children[1]);
	auto ok = FlatVector::GetDataMutable<bool>(FINANCE_STRUCT_CHILD(children[0]));
	auto reason = FlatVector::GetDataMutable<string_t>(reason_vector);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		const char *message = "ok";
		if (input.HasNull(row, 4)) {
			message = "null input";
		} else {
			double o = input.GetDouble(0, row);
			double h = input.GetDouble(1, row);
			double l = input.GetDouble(2, row);
			double c = input.GetDouble(3, row);
			if (!IsFinite(o) || !IsFinite(h) || !IsFinite(l) || !IsFinite(c)) {
				message = "non-finite price";
			} else if (!(o > 0.0) || !(h > 0.0) || !(l > 0.0) || !(c > 0.0)) {
				message = "non-positive price";
			} else if (h < std::max({o, l, c})) {
				message = "high below open/low/close";
			} else if (l > std::min({o, h, c})) {
				message = "low above open/high/close";
			}
		}
		ok[row] = strcmp(message, "ok") == 0;
		reason[row] = StringVector::AddString(reason_vector, message);
	}
}

static LogicalType ValidationType() {
	return FinanceStructType({{"ok", LogicalTypeId::BOOLEAN}, {"reason", LogicalTypeId::VARCHAR}});
}

//! A plausible decimal return: finite, >= -1 (a total loss is valid), and |r| <= max_abs (default 1.0).
static void ValidateReturnFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		double max_abs = args.ColumnCount() >= 2 ? input.GetDouble(1, row) : 1.0;
		double r = input.GetDouble(0, row);
		return IsFinite(r) && std::fabs(r) <= max_abs && r >= -1.0;
	});
}

static void IsFiniteFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [](const PreparedInputs &input, idx_t row) { return std::isfinite(input.GetDouble(0, row)); });
}

static void IsPriceFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		bool allow_zero = args.ColumnCount() >= 2 ? input.GetBool(1, row) : true;
		double x = input.GetDouble(0, row);
		return IsFinite(x) && (allow_zero ? x >= 0.0 : x > 0.0);
	});
}

static void IsRateFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		bool allow_negative = args.ColumnCount() >= 2 ? input.GetBool(1, row) : true;
		double x = input.GetDouble(0, row);
		return IsFinite(x) && (allow_negative || x >= 0.0);
	});
}

static void IsVolFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result,
	            [](const PreparedInputs &input, idx_t row) { return IsFinite(input.GetDouble(0, row)) && input.GetDouble(0, row) >= 0.0; });
}

static void IsOutlierZScoreFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		double threshold = args.ColumnCount() >= 4 ? input.GetDouble(3, row) : 3.0;
		double stddev = input.GetDouble(2, row);
		if (!(stddev > 0.0)) {
			return false;
		}
		return std::fabs((input.GetDouble(0, row) - input.GetDouble(1, row)) / stddev) > threshold;
	});
}

template <string (*PARSE)(const string &)>
static void ParseStringFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<string> parsed(args, 0, PARSE, string());
	ExecuteString(args, result, [&](const PreparedInputs &input, idx_t row) { return parsed.Get(input, row); });
}

static void ParseOptionKindFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	ParseStringFunction<ParseOptionKind>(args, state, result);
}

static void ParseExerciseStyleFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	ParseStringFunction<ParseExerciseStyle>(args, state, result);
}

static void ParseDayCountFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	ParseStringFunction<ParseDayCount>(args, state, result);
}

static void ParseCompoundingFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	ParseStringFunction<ParseCompounding>(args, state, result);
}

static void ParseReturnMethodFunction(DataChunk &args, ExpressionState &state, Vector &result) {
	ParseStringFunction<ParseReturnMethod>(args, state, result);
}

//! Upper-cased three-letter ASCII code; anything else returns NULL.
static void NormalizeCurrencyFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteString(args, result, [](const PreparedInputs &input, idx_t row) {
		auto currency = input.GetString(0, row);
		StringUtil::Trim(currency);
		currency = StringUtil::Upper(currency);
		if (currency.size() != 3 ||
		    !std::all_of(currency.begin(), currency.end(), [](char c) { return c >= 'A' && c <= 'Z'; })) {
			return string();
		}
		return currency;
	});
}

static void BusinessDayFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<BusinessCalendar> calendar(args, 1, ParseCalendar, BusinessCalendar::WEEKDAY);
	ExecuteBool(args, result, [&](const PreparedInputs &input, idx_t row) {
		auto date = input.GetDate(0, row);
		if (!Date::IsFinite(date)) {
			return -1;
		}
		return IsBusinessDay(date, calendar.Get(input, row)) ? 1 : 0;
	});
}

//! (date), (date, calendar), (date, BIGINT n), (date, calendar, BIGINT n).
static void NextPrevBusinessDayFunction(DataChunk &args, ExpressionState &, Vector &result, int direction) {
	bool has_calendar = args.ColumnCount() >= 2 && args.data[1].GetType().id() == LogicalTypeId::VARCHAR;
	ConfigArg<BusinessCalendar> calendar(args, has_calendar ? 1 : DConstants::INVALID_INDEX, ParseCalendar,
	                                     BusinessCalendar::WEEKDAY);
	idx_t offset_col = has_calendar ? 2 : 1;
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	PreparedInputs input(args);
	auto out = GetResultData<date_t>(result, constant);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		if (input.HasNull(row)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		int64_t n = args.ColumnCount() > offset_col ? input.GetInteger(offset_col, row) : 1;
		if (n < 0) {
			throw InvalidInputException("business-day offset must be non-negative, got %lld", (long long)n);
		}
		date_t d;
		if (!AdvanceBusinessDays(input.GetDate(0, row), n, direction, calendar.Get(input, row), d)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		out[row] = d;
	}
}

static void BusinessDaysBetweenFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ConfigArg<BusinessCalendar> calendar(args, 2, ParseCalendar, BusinessCalendar::WEEKDAY);
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	PreparedInputs input(args);
	auto out = GetResultData<int64_t>(result, constant);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		if (input.HasNull(row)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		auto start = input.GetDate(0, row);
		auto end = input.GetDate(1, row);
		if (!Date::IsFinite(start) || !Date::IsFinite(end)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		auto cal = calendar.Get(input, row);
		out[row] = end.days >= start.days ? BusinessDaysForward(start, end, cal) : -BusinessDaysForward(end, start, cal);
	}
}

//! Shared argument handling for (ts TIMESTAMP, calendar[, tz]) and (ts TIMESTAMPTZ, calendar). TIMESTAMP values
//! are wall-clock times in `tz` (default: the calendar's exchange zone); TIMESTAMPTZ values are instants.
template <class RESULT_TYPE, class FUNC>
static void ExecuteSession(DataChunk &args, Vector &result, FUNC func) {
	ConfigArg<BusinessCalendar> calendar(args, 1, ParseCalendar, BusinessCalendar::WEEKDAY);
	ConfigArg<SessionZone> zone(args, 2, ParseSessionZone, SessionZone::EXCHANGE);
	bool instant = args.data[0].GetType().id() == LogicalTypeId::TIMESTAMP_TZ;
	auto constant = AllInputsConstant(args);
	SetResultVectorType(result, constant);
	PreparedInputs input(args);
	auto out = GetResultData<RESULT_TYPE>(result, constant);
	auto row_count = constant && args.size() > 0 ? idx_t(1) : args.size();
	for (idx_t row = 0; row < row_count; row++) {
		if (input.HasNull(row)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		auto ts = input.GetTimestamp(0, row);
		if (!Timestamp::IsFinite(ts)) {
			SetResultNull(result, row, args.size(), constant);
			continue;
		}
		auto cal = calendar.Get(input, row);
		auto input_zone = instant ? SessionZone::UTC : zone.Get(input, row);
		auto local = ToExchangeLocal(ts.value, input_zone, cal);
		out[row] = func(local, cal);
	}
}

static void SessionDateFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteSession<date_t>(args, result, [](int64_t local, BusinessCalendar) {
		return date_t(int32_t(FloorDiv(local, MICROS_PER_DAY)));
	});
}

static void RegularSessionFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteSession<bool>(args, result, [](int64_t local, BusinessCalendar cal) { return IsRegularSession(local, cal); });
}
