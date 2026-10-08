static void PriceTransformFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		if (name == "avg") {
			return (input.GetDouble(0, row) + input.GetDouble(1, row) + input.GetDouble(2, row) +
			        input.GetDouble(3, row)) /
			       4.0;
		}
		if (name == "typ") {
			return (input.GetDouble(0, row) + input.GetDouble(1, row) + input.GetDouble(2, row)) / 3.0;
		}
		if (name == "median") {
			return (input.GetDouble(0, row) + input.GetDouble(1, row)) / 2.0;
		}
		return (input.GetDouble(0, row) + input.GetDouble(1, row) + 2.0 * input.GetDouble(2, row)) / 4.0;
	});
}

static void MicrostructureFunction(DataChunk &args, ExpressionState &, Vector &result, const string &name) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		if (name == "mid") {
			return (input.GetDouble(0, row) + input.GetDouble(1, row)) / 2.0;
		}
		if (name == "spread") {
			return input.GetDouble(1, row) - input.GetDouble(0, row);
		}
		if (name == "spread_bps") {
			double mid = (input.GetDouble(0, row) + input.GetDouble(1, row)) / 2.0;
			return (input.GetDouble(1, row) - input.GetDouble(0, row)) / mid * 10000.0;
		}
		if (name == "microprice") {
			double bid_px = input.GetDouble(0, row);
			double bid_size = input.GetDouble(1, row);
			double ask_px = input.GetDouble(2, row);
			double ask_size = input.GetDouble(3, row);
			return (ask_px * bid_size + bid_px * ask_size) / (bid_size + ask_size);
		}
		double bid_size = input.GetDouble(0, row);
		double ask_size = input.GetDouble(1, row);
		return (bid_size - ask_size) / (bid_size + ask_size);
	});
}

static void TradeSignFunction(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteDouble(args, result, [&](const PreparedInputs &input, idx_t row) {
		double price = input.GetDouble(0, row);
		double bid = input.GetDouble(1, row);
		double ask = input.GetDouble(2, row);
		if (price >= ask) {
			return 1.0;
		}
		if (price <= bid) {
			return -1.0;
		}
		if (args.ColumnCount() >= 4 && !input.IsNull(3, row)) {
			double prev = input.GetDouble(3, row);
			if (price > prev) {
				return 1.0;
			}
			if (price < prev) {
				return -1.0;
			}
		}
		return 0.0;
	});
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
