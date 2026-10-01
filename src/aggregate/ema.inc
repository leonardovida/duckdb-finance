struct EMAState {
	double mean;
	double tail;
	double tail_correction;
	double scale;
	double decay;
	double period;
	bool isset;
	idx_t count;
};

struct EMAOperation {
	template <class STATE>
	static void Initialize(STATE &state) {
		state.mean = state.tail = state.tail_correction = state.scale = 0.0;
		state.decay = 1.0;
		state.period = 20.0;
		state.isset = false;
		state.count = 0;
	}

	template <class STATE>
	static void NormalizeTail(STATE &state) {
		auto physical_tail = state.tail * state.scale;
		if (state.tail_correction != 0.0 && std::abs(state.tail_correction) >= 0.5 * std::abs(physical_tail)) {
			auto sum = physical_tail + state.tail_correction;
			state.tail_correction = SumError(physical_tail, state.tail_correction, sum);
			state.scale = std::abs(sum);
			state.tail = sum == 0.0 ? 0.0 : std::copysign(1.0, sum);
		}
		auto magnitude = std::abs(state.tail);
		if (magnitude > 0.0 && magnitude < 1e-100 && state.scale > std::numeric_limits<double>::denorm_min()) {
			auto scale = std::max(std::numeric_limits<double>::denorm_min(), state.scale * magnitude);
			state.tail = ScaledRatio(state.tail, state.scale, 1.0, scale, 1.0);
			state.scale = scale;
		} else if (magnitude == 0.0) {
			state.scale = 0.0;
		}
	}

	template <class STATE>
	static void UpdateRepeated(STATE &state, double value, double period, idx_t count) {
		if (!std::isfinite(period) || period < 1.0 || period > 2147483647.0 || std::trunc(period) != period) {
			throw InvalidInputException("EMA period must be a positive integer no greater than 2147483647");
		}
		if (!std::isfinite(value)) {
			throw InvalidInputException("EMA observations must be finite");
		}
		if (state.isset && state.period != period) {
			throw InvalidInputException("EMA period must be constant within a group");
		}
		if (count == 0) {
			return;
		}
		state.period = period;
		auto scale = std::abs(value);
		if (scale > state.scale) {
			auto ratio = state.scale / scale;
			auto physical = state.tail * state.scale;
			state.tail *= ratio;
			state.tail_correction += physical - state.tail * scale;
			state.scale = scale;
		}
		auto normalized = state.scale > 0.0 ? value / state.scale : 0.0;
		if (!state.isset) {
			state.mean = value; // Seed with the first non-NULL observation.
			state.isset = true;
		}
		auto alpha = 2.0 / (period + 1.0);
		auto decay = 1.0 - alpha;
		auto weight = alpha;
		double exponent = 0.0;
		if (count > 1 && alpha < 1.0) {
			exponent = static_cast<double>(count) * std::log1p(-alpha);
			decay = std::exp(exponent);
			weight = -std::expm1(exponent);
		}
		auto mean = ConvexCombination(state.mean, value, weight);
		if (count > 1 && alpha < 1.0 && state.mean != value) {
			auto previous = decay < 1e-100 ? ExponentialScaledRatio(state.mean, 1.0, 1.0, exponent)
			                                : decay * state.mean;
			mean = previous + weight * value;
			mean = std::min(std::max(state.mean, value), std::max(std::min(state.mean, value), mean));
		}
		auto old_tail = decay * state.tail;
		auto contribution = weight * normalized;
		auto tail = old_tail + contribution;
		auto correction = decay * state.tail_correction + SumError(old_tail, contribution, tail) * state.scale;
		correction += weight * value - contribution * state.scale;
		if (count > 1 && alpha < 1.0 &&
		    (decay == 0.0 || std::abs(tail) < 1e-100)) {
			auto magnitude = DecayedMagnitude(state.tail, state.scale, exponent);
			magnitude = std::max(magnitude, DecayedMagnitude(value, 1.0, std::log(weight)));
			auto scale = ScaleForMagnitude(magnitude);
			old_tail = ExponentialScaledRatio(state.tail, state.scale, scale, exponent);
			contribution = ExponentialScaledRatio(value, 1.0, scale, std::log(weight));
			tail = old_tail + contribution;
			correction = ExponentialScaledRatio(state.tail_correction, 1.0, 1.0, exponent) +
			             SumError(old_tail, contribution, tail) * scale;
			if (contribution == 0.0 && value != 0.0) {
				correction += weight * value;
			}
			state.scale = scale;
		}
		state.mean = mean;
		// Zero-seeded affine tail lets ordered merges append an entire block
		// without subtracting nearly equal seeded means or retaining history.
		state.tail = tail;
		state.tail_correction = correction;
		state.decay *= decay;
		state.count += count;
		NormalizeTail(state);
	}

	template <class INPUT_TYPE, class PERIOD_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &value, const PERIOD_TYPE &period,
	                              AggregateBinaryInput &, idx_t count) {
		UpdateRepeated(state, static_cast<double>(value), static_cast<double>(period), count);
	}

	template <class INPUT_TYPE, class PERIOD_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &value, const PERIOD_TYPE &period, AggregateBinaryInput &) {
		UpdateRepeated(state, static_cast<double>(value), static_cast<double>(period), 1);
	}

	template <class STATE, class OP>
	static void Combine(const STATE &source, STATE &target, AggregateInputData &) {
		if (!source.isset) {
			return;
		}
		if (!target.isset) {
			target = source;
			return;
		}
		if (target.period != source.period) {
			throw InvalidInputException("EMA period must be constant within a group");
		}
		auto scale = std::max(target.scale, source.scale);
		auto left = scale > 0.0 ? target.scale / scale : 0.0;
		auto right = scale > 0.0 ? source.scale / scale : 0.0;
		auto weighted_mean = source.decay * target.mean;
		auto physical_tail = source.tail * source.scale;
		auto mean = weighted_mean + physical_tail;
		mean += SumError(weighted_mean, physical_tail, mean) + source.tail_correction;
		auto old_tail = source.decay * target.tail * left;
		auto contribution = source.tail * right;
		auto tail = old_tail + contribution;
		auto correction = source.decay * target.tail_correction + source.tail_correction +
		                  SumError(old_tail, contribution, tail) * scale;
		if (contribution == 0.0 && source.tail != 0.0) {
			correction += physical_tail;
		}
		if (old_tail == 0.0 && target.tail != 0.0) {
			correction += source.decay * (target.tail * target.scale);
		}
		if (source.decay < 1e-100 || std::abs(tail) < 1e-100) {
			auto alpha = 2.0 / (source.period + 1.0);
			auto log_decay = alpha == 1.0 ? -std::numeric_limits<double>::infinity()
			                              : static_cast<double>(source.count) * std::log1p(-alpha);
			auto magnitude = DecayedMagnitude(target.tail, target.scale, log_decay);
			magnitude = std::max(magnitude, DecayedMagnitude(source.tail, source.scale, 0.0));
			scale = ScaleForMagnitude(magnitude);
			weighted_mean = ExponentialScaledRatio(target.mean, 1.0, 1.0, log_decay);
			physical_tail = ExponentialScaledRatio(source.tail, source.scale, 1.0, 0.0);
			mean = weighted_mean + physical_tail;
			mean += SumError(weighted_mean, physical_tail, mean) + source.tail_correction;
			old_tail = ExponentialScaledRatio(target.tail, target.scale, scale, log_decay);
			contribution = ExponentialScaledRatio(source.tail, source.scale, scale, 0.0);
			tail = old_tail + contribution;
			correction = ExponentialScaledRatio(target.tail_correction, 1.0, 1.0, log_decay) + source.tail_correction +
			             SumError(old_tail, contribution, tail) * scale;
			if (contribution == 0.0 && source.tail != 0.0) {
				correction += physical_tail;
			}
			if (old_tail == 0.0 && target.tail != 0.0) {
				correction += ExponentialScaledRatio(target.tail, target.scale, 1.0, log_decay);
			}
		}
		target.mean = mean;
		target.tail = tail;
		target.tail_correction = correction;
		target.decay *= source.decay;
		target.scale = scale;
		target.count += source.count;
		NormalizeTail(target);
	}

	template <class T, class STATE>
	static void Finalize(STATE &state, T &target, AggregateFinalizeData &finalize_data) {
		if (!state.isset) {
			finalize_data.ReturnNull();
			return;
		}
		target = state.mean;
		if (!std::isfinite(target)) {
			finalize_data.ReturnNull();
		}
	}

	static bool IgnoreNull() {
		return true;
	}
};

struct EMAUnaryOperation : public EMAOperation {
	template <class INPUT_TYPE, class STATE, class OP>
	static void Operation(STATE &state, const INPUT_TYPE &value, AggregateUnaryInput &) {
		UpdateRepeated(state, static_cast<double>(value), 20.0, 1);
	}

	template <class INPUT_TYPE, class STATE, class OP>
	static void ConstantOperation(STATE &state, const INPUT_TYPE &value, AggregateUnaryInput &, idx_t count) {
		UpdateRepeated(state, static_cast<double>(value), 20.0, count);
	}
};
